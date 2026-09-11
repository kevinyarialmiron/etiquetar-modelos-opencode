#!/usr/bin/env python3
"""Sondea los modelos de un proveedor contra su API real para detectar los que
no funcionan (deprecados/EOL, 404, timeouts) y escribirlos a
~/.config/opencode/data/nvidia-muertos.json para que gen-modelos.py los oculte.

El status "active" del catálogo (`opencode models --verbose`) es inútil: casi
todos los modelos deprecados de NVIDIA aparecen como "active". La única forma
confiable de saber si un modelo responde es llamarlo.

Uso:
    python3 probe-nvidia.py            # solo modelos de chat (rápido)
    python3 probe-nvidia.py --todo     # chat + embeddings + imagen (lento)
    python3 probe-nvidia.py --dudosos  # re-sondea solo los timeout/5xx con mas paciencia

Notas:
- Lee la key de nvidia de ~/.local/share/opencode/auth.json (no la imprime).
- 200 = vivo; 404/410/otros 4xx o timeout = muerto.
- Multiples intentos con concurrency cuidando límites de cuota (429 se salta).
- Es idempotente: regraba el archivo con el resultado más reciente.
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

MUERTOS = os.path.expanduser("~/.config/opencode/data/nvidia-muertos.json")
AUTH = os.path.expanduser("~/.local/share/opencode/auth.json")
BASE = "https://integrate.api.nvidia.com/v1"
CONCURRENCIA = 6
TIMEOUT = 20
TIMEOUT_CHAT = 40
# paciencia extra para el modo --dudosos (cold starts largos de NVIDIA)
TIMEOUT_DUDOSO = 180
INTENTOS_DUDOSO = 3


def es_dudoso(estado):
    """Un modelo es "dudoso" si un solo timeout/5xx lo tiene marcado y no fue
    confirmado muerto con un 4xx definitivo (410 EOL/404)."""
    return estado == "timeout" or (isinstance(estado, str) and estado[:1] == "5")


def cargar_previo():
    """Lee el baseline previo -> (muertos_dict, vivos_set)."""
    try:
        data = json.load(open(MUERTOS, encoding="utf-8"))
        return (data.get("muertos", {}) or {}), set(data.get("vivos", []) or [])
    except (FileNotFoundError, json.JSONDecodeError):
        return {}, set()


def bin_opencode():
    binoc = os.environ.get("OPENCODE_BIN", "")
    if binoc:
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
    inp = cap.get("input") or {}
    if out.get("image"):
        return "imagen"
    if out.get("audio") or (inp.get("audio") and not cap.get("temperature")):
        return "audio"
    if cap.get("temperature") or cap.get("toolcall") or "chat" in str(meta.get("model", "")):
        return "chat"
    return "embed"


def tiny_wav():
    import io
    import wave
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\x00\x00" * 1600)
    return buf.getvalue()


def probe(full_id, meta, key, solo_chat):
    kind = classify(meta)
    if solo_chat and kind != "chat":
        return full_id, {"ok": None, "skip": "solo_chat", "kind": kind}
    model_id = (meta.get("api") or {}).get("id") or full_id.split("/", 1)[1]
    headers = {"Authorization": f"Bearer {key}"}
    intentos = 2 if kind == "chat" else 1
    ultimo = None
    for i in range(intentos):
        try:
            if kind == "chat":
                headers["Content-Type"] = "application/json"
                r = requests.post(f"{BASE}/chat/completions",
                                  json={"model": model_id,
                                        "messages": [{"role": "user", "content": "hi"}],
                                        "max_tokens": 1},
                                  headers=headers, timeout=TIMEOUT_CHAT)
            elif kind == "imagen":
                r = requests.post(f"{BASE}/images/generations",
                                  json={"model": model_id, "prompt": "a red dot",
                                        "width": 16, "height": 16},
                                  headers=headers, timeout=TIMEOUT)
            elif kind == "embed":
                r = requests.post(f"{BASE}/embeddings",
                                  json={"model": model_id, "input": "hi", "input_type": "query"},
                                  headers=headers, timeout=TIMEOUT)
            else:
                r = requests.post(f"{BASE}/audio/transcriptions",
                                  files={"file": ("t.wav", tiny_wav(), "audio/wav")},
                                  data={"model": model_id},
                                  headers={"Authorization": f"Bearer {key}"},
                                  timeout=TIMEOUT)
            if r.status_code == 429 and i < intentos - 1:
                time.sleep(2)
                continue
            detalle = (r.text or "").strip().replace("\n", " ")[:120]
            return full_id, {"ok": r.status_code == 200,
                             "http": r.status_code, "kind": kind, "detalle": detalle}
        except Exception as e:
            ultimo = {"ok": False, "http": None, "kind": kind, "timeout": True,
                      "detalle": str(e)[:120]}
            if i < intentos - 1:
                time.sleep(1)
    return full_id, ultimo


def probe_chat_paciente(full_id, key):
    """Sondea SOLO el endpoint de chat de un modelo con mucha paciencia
    (los cold starts de NVIDIA llegan a +120 s). Intenta INTENTOS_DUDOSO veces."""
    model_id = full_id.split("/", 1)[1]
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
    for i in range(INTENTOS_DUDOSO):
        try:
            r = requests.post(f"{BASE}/chat/completions",
                              json={"model": model_id,
                                    "messages": [{"role": "user", "content": "hi"}],
                                    "max_tokens": 1},
                              headers=headers, timeout=TIMEOUT_DUDOSO)
            if r.status_code == 429 and i < INTENTOS_DUDOSO - 1:
                time.sleep(3)
                continue
            detalle = (r.text or "").strip().replace("\n", " ")[:120]
            return {"ok": r.status_code == 200, "http": r.status_code,
                    "detalle": detalle}
        except Exception as e:
            ultimo = {"ok": False, "http": None, "timeout": True,
                      "detalle": str(e)[:120]}
            if i < INTENTOS_DUDOSO - 1:
                time.sleep(2)
    return ultimo


def modo_dudosos(key):
    """Re-sondea con paciencia los modelos que quedaron marcados timeout/5xx y
    decide con datos: un 200 los pasa a vivos; un 4xx definitivo los confirma
    muertos; un timeout/5xx repetido los deja como dudosos."""
    try:
        data = json.load(open(MUERTOS, encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        data = {"vivos": [], "muertos": {}}
    prev_muertos = data.get("muertos", {}) or {}
    prev_vivos = set(data.get("vivos", []) or [])
    dudosos = [mid for mid, st in sorted(prev_muertos.items()) if es_dudoso(st)]
    if not dudosos:
        print("[dudosos] no hay modelos dudosos pendientes", file=sys.stderr)
        return

    print(f"[dudosos] re-sondeando {len(dudosos)} modelos con paciencia "
          f"({TIMEOUT_DUDOSO}s, hasta {INTENTOS_DUDOSO} intentos) ...", file=sys.stderr)
    resultados = {}
    with ThreadPoolExecutor(max_workers=4) as ex:
        futs = {ex.submit(probe_chat_paciente, mid, key): mid for mid in dudosos}
        for fut in as_completed(futs):
            resultados[futs[fut]] = fut.result()

    muertos = {mid: st for mid, st in prev_muertos.items() if not es_dudoso(st)}
    vivos = list(prev_vivos)
    for mid, res in sorted(resultados.items()):
        if res.get("ok") is True:
            vivos.append(mid)
            print(f"  [+ vivo] {mid} ({res.get('detalle', '')})", file=sys.stderr)
        elif res.get("http") in (429, 401, 403):
            muertos[mid] = prev_muertos[mid]
            print(f"  [= dudoso] {mid}: {res.get('http')} -> sin decisión", file=sys.stderr)
        elif res.get("http"):
            muertos[mid] = str(res.get("http"))
            print(f"  [= muerto] {mid}: {res.get('http')} definitivo", file=sys.stderr)
        else:
            muertos[mid] = "timeout"
            print(f"  [= dudoso] {mid}: sigue timeout tras reintentos", file=sys.stderr)

    vivos = sorted(set(vivos))
    os.makedirs(os.path.dirname(MUERTOS), exist_ok=True)
    payload = {"actualizado": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "proveedor": "nvidia", "vivos": vivos, "muertos": muertos}
    json.dump(payload, open(MUERTOS, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"[dudosos] vivos:{len(vivos)} muertos:{len(muertos)} -> {MUERTOS}", file=sys.stderr)


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

    if not os.path.exists(AUTH):
        print("[warn] no existe auth.json; no hay nada que sondear", file=sys.stderr)
        return
    auth = json.load(open(AUTH, encoding="utf-8"))
    key = (auth.get("nvidia") or {}).get("key")
    if not key:
        print("[warn] no hay key de nvidia en auth.json", file=sys.stderr)
        return

    if "--dudosos" in sys.argv:
        modo_dudosos(key)
        return

    solo_chat = "--todo" not in sys.argv
    verbose = leer_verbose()
    solo = {}
    for full_id, meta in verbose:
        if full_id.split("/", 1)[0] == "nvidia":
            solo[full_id] = meta

    print(f"[probe] {len(solo)} modelos nvidia (modo {'chat' if solo_chat else 'todo'}) ...",
          file=sys.stderr)
    resultados = {}
    with ThreadPoolExecutor(max_workers=CONCURRENCIA) as ex:
        futs = {ex.submit(probe, full_id, meta, key, solo_chat): full_id
                for full_id, meta in solo.items()}
        for fut in as_completed(futs):
            full_id, res = fut.result()
            resultados[full_id] = res

    prev_muertos, prev_vivos = cargar_previo()

    muertos = {}
    vivos = set()
    for full_id, res in sorted(resultados.items()):
        if res.get("skip"):
            # No se probó en este modo (p.ej. el modo chat saltea embed/imagen/audio):
            # conservar el estado previo para no borrar datos de un run --todo.
            if full_id in prev_muertos:
                muertos[full_id] = prev_muertos[full_id]
            elif full_id in prev_vivos:
                vivos.add(full_id)
            continue
        if res.get("ok") is True:
            vivos.add(full_id)
            continue
        http = res.get("http")
        if http is None:
            # timeout / error de red: NUNCA degradar una evidencia definitiva previa
            # (410 EOL / 404), ni matar un modelo antes confirmado vivo por un solo
            # timeout (cold start). Si no hay historial, queda como dudoso.
            if full_id in prev_muertos:
                muertos[full_id] = prev_muertos[full_id]
            elif full_id in prev_vivos:
                vivos.add(full_id)
            else:
                muertos[full_id] = "timeout"
            continue
        if http in (429, 401, 403):
            # sin decisión (cuota/auth): conservar el estado previo si lo había
            if full_id in prev_muertos:
                muertos[full_id] = prev_muertos[full_id]
            elif full_id in prev_vivos:
                vivos.add(full_id)
            continue
        if http >= 500:
            # 5xx = error transitorio del servidor, NO prueba de muerte.
            # No matar a un modelo antes vivo; si no hay historial, queda dudoso.
            if full_id in prev_muertos:
                muertos[full_id] = prev_muertos[full_id]
            elif full_id in prev_vivos:
                vivos.add(full_id)
            else:
                muertos[full_id] = str(http)
            continue
        # 4xx definitivo (404/410/...) -> muerto confirmado
        muertos[full_id] = str(http)

    vivos = sorted(vivos)
    os.makedirs(os.path.dirname(MUERTOS), exist_ok=True)
    payload = {"actualizado": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "proveedor": "nvidia", "vivos": vivos, "muertos": muertos}
    json.dump(payload, open(MUERTOS, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    n_dudosos = sum(1 for s in muertos.values() if es_dudoso(s))
    print(f"[probe] vivos:{len(vivos)} muertos:{len(muertos)} "
          f"(dudosos:{n_dudosos}) -> {MUERTOS}", file=sys.stderr)


if __name__ == "__main__":
    main()