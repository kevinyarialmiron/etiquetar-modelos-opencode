#!/usr/bin/env python3
"""Sondea los modelos de chat de TODOS los proveedores contra su API real para
detectar los que no responden (EOL/404/410) y escribirlos a
~/.config/opencode/data/probe-<prov>.json para que gen-modelos.py los oculte.

A diferencia de probe-nvidia.py (que solo cubre NVIDIA y habla el endpoint
integrate.api.nvidia.com), este usa la metadata `api.url`/`api.npm` que publica
`opencode models --verbose` para cada modelo: la mayoría son OpenAI-compatible
y basta con POST {url}/chat/completions. Para los proveedores cuyo binario
abre su SDK nativo (google, groq, vercel, cloudflare) hay una tabla de base-URLs.

Uso:
    python3 probe-proveedores.py                 # todos los proveedores (chat)
    python3 probe-proveedores.py --prov deepseek # un solo proveedor (smoke test)
    python3 probe-proveedores.py --prov openrouter --prov deepseek

Semántica conservadora (NUNCA mata un modelo por falta de saldo):
    200                       -> vivo
    404/410 (EOL)             -> muerto (solo si el endpoint es confiable)
    400 con "not found"/EOL   -> muerto
    401/402/403/429 (auth/quota/sin saldo) -> NO verificado (se conserva previo)
    5xx / timeout             -> transitorio (se conserva previo; dudoso si no hay)
"""
import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    import requests
except ImportError:
    print("[error] falta el paquete 'requests'. Instalalo con: python -m pip install requests",
          file=sys.stderr)
    sys.exit(2)

DATA = os.path.expanduser("~/.config/opencode/data")
AUTH = os.path.expanduser("~/.local/share/opencode/auth.json")

CONCURRENCIA = 8
TIMEOUT_CHAT = 30

# Base-URLs para proveedores cuyo binario NO publica `api.url` (SDK nativo).
# A todos se les agrega `/chat/completions` (formato OpenAI-compatible).
# Nota: `vercel` y `cloudflare-ai-gateway` no se usan en esta config (se quitaron
# de los proveedores activos), pero el soporte queda por si otro usuario los
# autentica. `vercel` está en NO_PROBEAR igualmente: su endpoint exige el
# contexto/sesión del propio opencode y no es verificable desde fuera.
BASE_OVERRIDE = {
    "google": "https://generativelanguage.googleapis.com/v1beta/openai",
    "groq": "https://api.groq.com/openai/v1",
    "vercel": "https://ai-gateway.vercel.app/v1",
}
# Proveedores cuyo endpoint conocemos con certeza => un 404/410 es evidencia de
# muerte confiable. Los que no estén acá (gateways construidos a mano) se
# clasifican más conservador: un 404 solo mata si el body lo delata.
ENDPOINT_CONFIABLE = {
    "nvidia", "openrouter", "deepseek", "huggingface", "ollama-cloud",
    "opencode", "google", "groq",
}

# Proveedores cuyo endpoint NO se puede sondear de forma confiable a nivel de
# API (sin sesión/contexto del propio opencode, o con URL de gateway opaca).
# Se saltean para no producir falsos muertos (un 404 del sitio se confundiría
# con un modelo retirado).
NO_PROBEAR = {"vercel", "opencode"}

# Patrones de body que indican "modelo no existe / end of life". Se evita
# casar páginas web o errores genéricos de infraestructura.
RE_MUERTO = re.compile(
    r"(does not exist|no such|end of life|deprecated|"
    r"model.*(?:retired|discontinued|removed|unavailable)|"
    r"could not be found|unknown model|resource not found|"
    r"not found.*model)", re.I)


def bin_opencode():
    binoc = os.environ.get("OPENCODE_BIN", "")
    if binoc and os.path.exists(binoc):
        return binoc
    if sys.platform == "win32":
        return "opencode"
    for cand in ("~/.opencode/bin/opencode", "~/.local/bin/opencode", "/usr/local/bin/opencode"):
        p = os.path.expanduser(cand)
        if os.path.exists(p):
            return p
    return "opencode"


def leer_verbose():
    binoc = bin_opencode()
    out = subprocess.run([binoc, "models", "--verbose"],
                         capture_output=True, text=True,
                         encoding="utf-8", errors="replace")
    rows = []
    cur = None
    buf = []
    for line in out.stdout.splitlines():
        s = line.rstrip("\n")
        if not s.strip():
            continue
        if not s.startswith((" ", "{")) and "/" in s:
            if cur is not None and buf:
                try:
                    rows.append((cur, json.loads("\n".join(buf))))
                except (json.JSONDecodeError, ValueError):
                    rows.append((cur, {}))
                buf = []
            cur = s.strip()
        elif cur is not None:
            buf.append(s)
    if cur is not None and buf:
        try:
            rows.append((cur, json.loads("\n".join(buf))))
        except (json.JSONDecodeError, ValueError):
            rows.append((cur, {}))
    return rows


def classify(meta):
    cap = meta.get("capabilities") or {}
    out = cap.get("output") or {}
    if out.get("image"):
        return "imagen"
    if out.get("audio"):
        return "audio"
    if cap.get("temperature") or cap.get("toolcall") or "chat" in str(meta.get("model", "")):
        return "chat"
    return "embed"


def provider_base(prov, meta, auth_provider):
    """Devuelve la base URL del endpoint de chat para un proveedor/modelo."""
    api = meta.get("api") or {}
    url = api.get("url")
    if url:
        return url.rstrip("/")
    if prov == "cloudflare-ai-gateway":
        # el metadata.gatewayId trae la URL completa del gateway (con \n al final)
        # (soporte opcional: cloudflare-ai-gateway no está en la config activa)
        meta_cf = (auth_provider or {}).get("metadata") or {}
        gw = (meta_cf.get("gatewayId") or "").strip()
        if gw:
            return gw.rstrip("/") + "/openai/v1"
    return BASE_OVERRIDE.get(prov, "")


def probe(full_id, meta, key, prov, confiable, auth_provider):
    kind = classify(meta)
    if kind != "chat":
        return full_id, {"skip": f"solo_chat:{kind}"}
    api = meta.get("api") or {}
    model_id = api.get("id") or full_id.split("/", 1)[1]
    base = provider_base(prov, meta, auth_provider)
    if not base:
        return full_id, {"skip": "sin-endpoint"}
    endpoint = f"{base}/chat/completions"
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    try:
        r = requests.post(endpoint,
                          json={"model": model_id,
                                "messages": [{"role": "user", "content": "hi"}],
                                "max_tokens": 1},
                          headers=headers, timeout=TIMEOUT_CHAT)
        detalle = (r.text or "").strip().replace("\n", " ")[:160]
        return full_id, {"ok": r.status_code == 200, "http": r.status_code,
                         "kind": kind, "detalle": detalle,
                         "confiable": confiable}
    except Exception as e:
        return full_id, {"ok": False, "http": None, "kind": kind,
                         "timeout": True, "confiable": confiable,
                         "detalle": str(e)[:160]}


def decide_muerto(res):
    """Decide el estado final de un resultado. Devuelve:
       'vivo' | 'muerto' | 'no-verificado' | ('dudoso', codigo)."""
    http = res.get("http")
    if res.get("ok") is True:
        return "vivo"
    if http is None:
        return "dudoso"  # timeout / error de red
    if http in (401, 402, 403, 429):
        return "no-verificado"  # auth/cuota/sin saldo: NUNCA muerto
    if http >= 500:
        return "dudoso"  # transitorio
    # 4xx definitivo (400/404/410/...)
    detalle = res.get("detalle") or ""
    if http in (404, 410):
        if res.get("confiable"):
            return "muerto"
        # endpoint no 100% confiable: solo muerto si el body es inequívoco
        return "muerto" if RE_MUERTO.search(detalle) else "no-verificado"
    if http == 400 and RE_MUERTO.search(detalle):
        return "muerto"
    # otros 4xx (400 sin pista, 422, ...) -> no verificado, no es evidencia
    return "no-verificado"


def cargar_previo(path):
    try:
        data = json.load(open(path, encoding="utf-8"))
        return (data.get("muertos", {}) or {}), set(data.get("vivos", []) or [])
    except (FileNotFoundError, json.JSONDecodeError):
        return {}, set()


def procesar_proveedor(prov, modelos, key, auth_provider):
    """Sondea todos los modelos de chat de un proveedor y escribe probe-<prov>.json."""
    path = os.path.join(DATA, f"probe-{prov}.json")
    prev_muertos, prev_vivos = cargar_previo(path)
    # compat: si nunca se corrió el genérico, heredar el baseline de nvidia-muertos.json
    if prov == "nvidia" and not prev_muertos and not prev_vivos:
        prev_muertos, prev_vivos = cargar_previo(os.path.join(DATA, "nvidia-muertos.json"))

    confiable = prov in ENDPOINT_CONFIABLE

    print(f"[probe:{prov}] {len(modelos)} modelos (chat) ...", file=sys.stderr)
    resultados = {}
    with ThreadPoolExecutor(max_workers=CONCURRENCIA) as ex:
        futs = {ex.submit(probe, full_id, meta, key, prov, confiable, auth_provider): full_id
                for full_id, meta in modelos.items()}
        for fut in as_completed(futs):
            full_id, res = fut.result()
            resultados[full_id] = res

    muertos = {}
    vivos = set()
    no_verif = set()
    for full_id, res in sorted(resultados.items()):
        if res.get("skip"):
            # no probado en este modo (no es chat / sin endpoint): conservar previo
            if full_id in prev_muertos:
                muertos[full_id] = prev_muertos[full_id]
            elif full_id in prev_vivos:
                vivos.add(full_id)
            continue
        decision = decide_muerto(res)
        if decision == "vivo":
            vivos.add(full_id)
        elif decision == "muerto":
            muertos[full_id] = str(res.get("http"))
        elif decision == "no-verificado":
            # conservar estado previo si lo había; si no, queda sin registrar
            if full_id in prev_muertos:
                muertos[full_id] = prev_muertos[full_id]
            elif full_id in prev_vivos:
                vivos.add(full_id)
            else:
                no_verif.add(full_id)
        else:  # dudoso
            if full_id in prev_muertos:
                muertos[full_id] = prev_muertos[full_id]
            elif full_id in prev_vivos:
                vivos.add(full_id)
            else:
                muertos[full_id] = "timeout"

    vivos = sorted(vivos)
    os.makedirs(DATA, exist_ok=True)
    payload = {"actualizado": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "proveedor": prov, "vivos": vivos, "muertos": muertos}
    json.dump(payload, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"[probe:{prov}] vivos:{len(vivos)} muertos:{len(muertos)} "
          f"no-verificados:{len(no_verif)} -> {path}", file=sys.stderr)
    return prov, len(vivos), len(muertos), len(no_verif)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

    args = sys.argv[1:]
    solo_providers = set()
    i = 0
    while i < len(args):
        if args[i] == "--prov" and i + 1 < len(args):
            solo_providers.add(args[i + 1])
            i += 2
        else:
            i += 1

    if not os.path.exists(AUTH):
        print("[warn] no existe auth.json; no hay nada que sondear", file=sys.stderr)
        return
    auth = json.load(open(AUTH, encoding="utf-8"))

    verbose = leer_verbose()
    by_prov = {}
    for full_id, meta in verbose:
        prov = (meta.get("providerID") or full_id.split("/", 1)[0])
        by_prov.setdefault(prov, {})[full_id] = meta

    total = {"vivos": 0, "muertos": 0, "no_verif": 0}
    for prov in sorted(by_prov):
        if solo_providers and prov not in solo_providers:
            continue
        if prov in NO_PROBEAR:
            print(f"[probe:{prov}] salteado: endpoint no verificable sin contexto (no se sondea)",
                  file=sys.stderr)
            continue
        cred = auth.get(prov)
        key = None
        if isinstance(cred, dict):
            key = cred.get("key")
        if not key:
            print(f"[probe:{prov}] salteado: sin key en auth.json", file=sys.stderr)
            continue
        r = procesar_proveedor(prov, by_prov[prov], key, cred)
        total["vivos"] += r[1]
        total["muertos"] += r[2]
        total["no_verif"] += r[3]

    print(f"[probe] TOTAL vivos:{total['vivos']} muertos:{total['muertos']} "
          f"no-verificados:{total['no_verif']}", file=sys.stderr)


if __name__ == "__main__":
    main()