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

COST_EMOJI = ["🌱", "❶", "❷", "❸", "❹", "❺", "❻", "❼", "❽", "❾"]
MEDAL = {1: "🥇", 2: "🥈", 3: "🥉", 4: "🏅"}
EMOJIS = "⭐🥇🥈🥉🏅🌱🪙❶❷❸❹❺❻❼❽❾❗❿"


def bin_opencode():
    p = os.path.expanduser("~/.opencode/bin/opencode")
    if os.path.exists(p):
        return p
    return shutil.which("opencode") or "opencode"


def leer_verbose():
    """Parsea `opencode models --verbose` -> [(full_id, dict_metadata)]."""
    out = subprocess.run([bin_opencode(), "models", "--verbose"],
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


def main():
    rules = {"override": {}, "niveles": {}}
    try:
        rules = json.load(open(RULES))
    except (FileNotFoundError, json.JSONDecodeError):
        print("[warn] rules no disponibles; solo usará medallas del config actual", file=sys.stderr)
    override = rules.get("override", {})
    niveles = rules.get("niveles", {})

    config = {}
    try:
        config = json.load(open(CONFIG))
    except (FileNotFoundError, json.JSONDecodeError):
        print("[warn] opencode.json no existe; se creará al aplicar", file=sys.stderr)
    provider_cfg = config.setdefault("provider", {})

    verbose = leer_verbose()
    visibles = {}
    meta_by_full = {}
    for full_id, meta in verbose:
        prov, rest = full_id.split("/", 1)
        visibles.setdefault(prov, []).append(rest)
        meta_by_full[full_id] = meta

    rows = []
    for prov, ids in sorted(visibles.items()):
        modelos_config = provider_cfg.get(prov, {}).get("models", {})
        for cfg_key in sorted(ids):
            full_id = f"{prov}/{cfg_key}"
            name_by_meta, cost_out, ctx = meta_util(meta_by_full.get(full_id, {}))

            nivel = override.get(full_id, 0) or override.get(cfg_key, 0)
            if not nivel:
                cur = modelos_config.get(cfg_key)
                if isinstance(cur, dict):
                    nivel = parse_medalla_actual(cur.get("name"))
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

            if prov == "ollama":
                cost_out = 0.0

            ceil = cost_emoji(cost_out)
            cur_name = modelos_config.get(cfg_key) if isinstance(modelos_config, dict) else None
            cur_name = cur_name.get("name") if isinstance(cur_name, dict) else None
            base = strip_emojis(cur_name) or strip_emojis(name_by_meta) or \
                cfg_key.split("/")[-1].replace("-", " ").title()
            star = "⭐" if nivel == 1 else ""
            medalla = MEDAL.get(nivel, "")
            prefijo = f"{star}{medalla}{ceil}".strip()
            name_final = (prefijo + " " + base).strip() if prefijo else base

            rows.append({
                "provider": prov,
                "id": full_id,
                "name": name_final,
                "nivel": nivel,
                "cost_out": round(cost_out, 3) if cost_out is not None else None,
                "contexto": ctx,
            })

    with open(OUTDATA, "w") as f:
        json.dump({"modelos": rows}, f, ensure_ascii=False, indent=1)

    if "--apply" in sys.argv:
        for prov, ids in sorted(visibles.items()):
            pm = provider_cfg.setdefault(prov, {})
            modelos_config = pm.setdefault("models", {})
            for cfg_key in ids:
                r = next(x for x in rows if x["provider"] == prov and x["id"] == f"{prov}/{cfg_key}")
                entry = modelos_config.get(cfg_key)
                if isinstance(entry, dict):
                    entry["name"] = r["name"]
                else:
                    entry = {"name": r["name"]}
                modelos_config[cfg_key] = entry
        json.dump(config, open(CONFIG, "w"), ensure_ascii=False, indent=2)
        open(CONFIG, "a").write("\n")
        print(f"[apply] opencode.json actualizado ({len(rows)} modelos)")
    else:
        from collections import Counter
        c = Counter(r["provider"] for r in rows)
        print("[preview] total:", len(rows), "| por provider:", dict(c))
        for r in rows[:20]:
            print(f"  {r['id']:<46} -> {r['name']}")


if __name__ == "__main__":
    main()