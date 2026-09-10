#!/usr/bin/env python3
"""
Gen-etiquetas de modelos para opencode.

FUENTE ÚNICA:   `opencode models --verbose`  (id + name + cost + limit de los modelos
                visibles; NO depende del catálogo cacheado ~/.cache/opencode/models.json).
REGLAS:         ~/.config/opencode/data/models-rank.json  (calidad: override + patrones)

Produce:
  - data/modelos.json  (dataset para el comando /modelos)
  - --apply: actualiza provider.*.models.*.name en opencode.json

Formato de nombre: [⭐]medalla[emoji costo]  [nombre]
  nivel 1 -> "⭐🥇{costo} Nombre"   nivel 2/3/4 -> "{medalla}{costo} Nombre"
  nivel 0 (evitar) -> "{costo} Nombre"  (solo costo)

Escala de costo (output $ / 1M tokens):
  $0 -> 🌱 (gratis)   $0-$1 -> 🪙 (centavos)   $1-2 -> ❶   $2-3 -> ❷   $3-4 -> ❸   $4-5 -> ❹
  $5-6 -> ❺❗   ...   $9-10 -> ❾❗   >=$10 -> ❿❗
"""
import json
import os
import re
import shutil
import subprocess
import sys

CONFIG = os.path.expanduser("~/.config/opencode/opencode.json")
RULES = os.path.expanduser("~/.config/opencode/data/models-rank.json")
OUTDATA = os.path.expanduser("~/.config/opencode/data/modelos.json")
MUERTOS = os.path.expanduser("~/.config/opencode/data/nvidia-muertos.json")

COST_EMOJI = ["🌱", "❶", "❷", "❸", "❹", "❺", "❻", "❼", "❽", "❾"]
MEDAL = {1: "🥇", 2: "🥈", 3: "🥉", 4: "🏅"}
TIPO_EMOJI = {"chat": "", "embed": "🧩", "imagen": "🖼️", "audio": "🎙️", "otro": "🧩"}
EMOJIS = "⭐🥇🥈🥉🏅🌱🪙❶❷❸❹❺❻❼❽❾❗❿🧩🖼️🎙️💀"


def bin_opencode():
    env = os.environ.get("OPENCODE_BIN")
    if env and os.path.exists(env):
        return env
    p = os.path.expanduser("~/.opencode/bin/opencode")
    if os.path.exists(p):
        return p
    return shutil.which("opencode") or "opencode"


def leer_verbose():
    """Parsea `opencode models --verbose` -> [(full_id, dict_metadata)]."""
    binoc = bin_opencode()
    if os.name == "nt" and binoc.lower().endswith((".cmd", ".bat")):
        # shim de npm: no es un exe directo; hay que ejecutarlo con shell
        cmdline = " ".join(f'"{c}"' for c in [binoc, "models", "--verbose"])
        out = subprocess.run(cmdline, capture_output=True, text=True, shell=True, encoding="utf-8")
    elif os.name == "nt" and binoc.lower().endswith(".ps1"):
        # shim PowerShell de npm: invocar via powershell.exe
        cmdline = f'powershell -NoProfile -ExecutionPolicy Bypass -File "{binoc}" models --verbose'
        out = subprocess.run(cmdline, capture_output=True, text=True, shell=True, encoding="utf-8")
    else:
        out = subprocess.run([binoc, "models", "--verbose"],
                             capture_output=True, text=True)
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


def meta_util(meta):
    """Devuelve (name, cost_output, context) a partir de la metadata JSON."""
    name = meta.get("name")
    cost = meta.get("cost")
    co = None
    if isinstance(cost, dict):
        co = cost.get("output") if cost.get("output") is not None else cost.get("input")
    lim = meta.get("limit")
    ctx = lim.get("context") if isinstance(lim, dict) else None
    return name, co, ctx


def cost_emoji(out):
    if out is None:
        return ""
    if out == 0:
        return "🌱"
    if out < 1:
        return "🪙"
    n = int(out)
    if n >= 10:
        return "❿❗"
    return COST_EMOJI[n] + ("❗" if n >= 5 else "")


def strip_emojis(t):
    if not t:
        return ""
    t = re.sub(r"^[" + EMOJIS + r"\s]+", "", t).strip()
    t = re.sub(r"[" + EMOJIS + r"\s]+$", "", t).strip()
    return t


def parse_medalla_actual(name):
    if not name:
        return 0
    for lvl, m in MEDAL.items():
        if m in name:
            return lvl
    return 0


def detect_tipo(meta):
    """Clasifica chat/embed/imagen/audio a partir de las capabilities del verbose."""
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


def cargar_muertos():
    try:
        data = json.load(open(MUERTOS, encoding="utf-8"))
        return data.get("muertos", {}) or {}
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def es_oculto(full_id, muertos, ocultar_patrones):
    if full_id in muertos:
        return True
    for pat in ocultar_patrones:
        try:
            if re.search(pat, full_id, re.I):
                return True
        except re.error:
            continue
    return False


def base_original(cfg_key, cur_name, name_by_meta):
    return strip_emojis(cur_name) or strip_emojis(name_by_meta) or \
        cfg_key.split("/")[-1].replace("-", " ").title()


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

    rules = {"override": {}, "niveles": {}}
    try:
        rules = json.load(open(RULES, encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        print("[warn] rules no disponibles; solo usará medallas del config actual", file=sys.stderr)
    override = rules.get("override", {})
    niveles = rules.get("niveles", {})
    ocultar_patrones = rules.get("ocultar", []) or []
    muertos = cargar_muertos()

    config = {}
    try:
        config = json.load(open(CONFIG, encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        print("[warn] opencode.json no existe; se creará al aplicar", file=sys.stderr)
    provider_cfg = config.setdefault("provider", {})

    print(f"[bin] opencode: {bin_opencode()}", file=sys.stderr)

    verbose = leer_verbose()
    visibles = {}
    meta_by_full = {}
    for full_id, meta in verbose:
        prov, rest = full_id.split("/", 1)
        visibles.setdefault(prov, []).append(rest)
        meta_by_full[full_id] = meta

    rows = []
    n_ocultos = 0
    for prov, ids in sorted(visibles.items()):
        modelos_config = provider_cfg.get(prov, {}).get("models", {})
        for cfg_key in sorted(ids):
            full_id = f"{prov}/{cfg_key}"
            name_by_meta, cost_out, ctx = meta_util(meta_by_full.get(full_id, {}))
            tipo = detect_tipo(meta_by_full.get(full_id, {}))
            oculto = es_oculto(full_id, muertos, ocultar_patrones)

            nivel = override.get(full_id, 0) or override.get(cfg_key, 0)
            if not nivel:
                for lvl, pats in sorted(niveles.items(), key=lambda x: int(x[0])):
                    if not isinstance(pats, list):
                        continue
                    for pat in pats:
                        try:
                            if re.search(pat, full_id, re.I):
                                nivel = int(lvl)
                                break
                        except re.error:
                            continue
                    if nivel:
                        break
            # las reglas mandan; la medalla ya aplicada en opencode.json se
            # conserva solo como fallback (ej: usuarios sin regla pero con
            # nombre editado a mano)
            if not nivel:
                cur = modelos_config.get(cfg_key)
                if isinstance(cur, dict):
                    nivel = parse_medalla_actual(cur.get("name"))

            if prov == "ollama":
                cost_out = 0.0

            ceil = cost_emoji(cost_out)
            cur_name = modelos_config.get(cfg_key) if isinstance(modelos_config, dict) else None
            cur_name = cur_name.get("name") if isinstance(cur_name, dict) else None
            base = base_original(cfg_key, cur_name, name_by_meta)
            star = "⭐" if nivel == 1 else ""
            medalla = MEDAL.get(nivel, "")
            tag = TIPO_EMOJI.get(tipo, "")
            if oculto:
                n_ocultos += 1
                continue
            prefijo = f"{star}{medalla}{tag}{ceil}".strip()
            name_final = (prefijo + " " + base).strip() if prefijo else base

            rows.append({
                "provider": prov,
                "id": full_id,
                "tipo": tipo,
                "name": name_final,
                "nivel": nivel,
                "cost_out": round(cost_out, 3) if cost_out is not None else None,
                "contexto": ctx,
            })

    with open(OUTDATA, "w", encoding="utf-8") as f:
        json.dump({"modelos": rows}, f, ensure_ascii=False, indent=1)

    if "--apply" in sys.argv:
        n_ocultos_aplicados = 0
        for prov, ids in sorted(visibles.items()):
            pm = provider_cfg.setdefault(prov, {})
            modelos_config = pm.setdefault("models", {})
            for cfg_key in ids:
                full_id = f"{prov}/{cfg_key}"
                if es_oculto(full_id, muertos, ocultar_patrones):
                    entry = modelos_config.get(cfg_key)
                    cur = None
                    if isinstance(entry, dict):
                        cur = entry.get("name")
                    elif isinstance(entry, str):
                        cur = entry
                    base = base_original(cfg_key, cur,
                                         meta_util(meta_by_full.get(full_id, {}))[0])
                    # todo muerto se marca con calavera: se crea la entrada aunque
                    # no existiera antes para que el picker lo muestre claramente
                    if isinstance(entry, dict):
                        entry["name"] = f"💀 {base}"
                    else:
                        entry = {"name": f"💀 {base}"}
                    modelos_config[cfg_key] = entry
                    n_ocultos_aplicados += 1
                    continue
                r = next(x for x in rows if x["provider"] == prov and x["id"] == full_id)
                entry = modelos_config.get(cfg_key)
                if isinstance(entry, dict):
                    entry["name"] = r["name"]
                else:
                    entry = {"name": r["name"]}
                modelos_config[cfg_key] = entry
        json.dump(config, open(CONFIG, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        open(CONFIG, "a").write("\n")
        print(f"[apply] opencode.json actualizado ({len(rows)} modelos | {n_ocultos} ocultos | {n_ocultos_aplicados} marcados 💀)")
    else:
        from collections import Counter
        c = Counter(r["provider"] for r in rows)
        print("[preview] total:", len(rows), "| ocultos:", n_ocultos, "| por provider:", dict(c))
        for r in rows[:20]:
            print(f"  {r['id']:<46} -> {r['name']}")


if __name__ == "__main__":
    main()