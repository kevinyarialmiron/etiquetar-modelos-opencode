#!/usr/bin/env python3
"""Ordena la pestaña Favoritos del picker /models de opencode.

Criterio:
  1) calidad ASCENDENTE (nivel 1 = mejores, arriba); sin medalla al final
  2) dentro del mismo nivel, costo DESCENDENTE (más caro primero), gratis al final
  3) desempate alfabético por modelID

Solo toca la lista `favorite` del state. Escribe backup `.bak-orden-<ts>`.

Multiplataforma: también se usa desde Windows (instalar.ps1).

Uso:
  python3 ordenar-favoritos.py <state.json> <modelos.json>
"""
import datetime
import json
import os
import sys


def resolve(meta, providerID, modelID):
    """Devuelve (nivel, costo) aunque el id no esté 1:1 en modelos.json."""
    full = f"{providerID}/{modelID}"
    if full in meta:
        return meta[full]
    # mismo proveedor, modelo coincide como sufijo (proveedores anidados tipo openrouter/x/y)
    pref = f"{providerID}/"
    hits = [(k, v) for k, v in meta.items() if k.startswith(pref) and k.endswith("/" + modelID)]
    if hits:
        return _best(hits)
    # cualquier proveedor con ese modelo
    hits = [(k, v) for k, v in meta.items() if k.endswith("/" + modelID)]
    if hits:
        return _best(hits)
    return (0, None)


def _best(hits):
    def k(item):
        nivel, cost = item[1]
        lvl = nivel if nivel and nivel >= 1 else 99
        c = cost if cost is not None else -1
        return (lvl, -c)
    return sorted(hits, key=k)[0][1]


def sortkey(r, meta):
    nivel, cost = resolve(meta, r.get("providerID", ""), r.get("modelID", ""))
    lvl = nivel if nivel and nivel >= 1 else 99
    c = cost if cost is not None else -1
    return (lvl, -c, r.get("modelID", ""))


def main():
    if len(sys.argv) != 3:
        print("uso: python3 ordenar-favoritos.py <state.json> <modelos.json>", file=sys.stderr)
        sys.exit(2)
    state_path, data_path = sys.argv[1], sys.argv[2]

    try:
        state = json.load(open(state_path, encoding="utf-8"))
    except FileNotFoundError:
        print(f"No existe {state_path} (¿opencode nunca corrió?)", file=sys.stderr)
        sys.exit(1)
    try:
        data = json.load(open(data_path, encoding="utf-8"))
    except FileNotFoundError:
        print(f"No existe {data_path}. Regeneralo: python3 {os.path.dirname(os.path.abspath(data_path))}/gen-modelos.py", file=sys.stderr)
        sys.exit(1)

    meta = {r["id"]: (r.get("nivel") or 0, r.get("cost_out")) for r in data.get("modelos", [])}

    fav = state.get("favorite", [])
    if not isinstance(fav, list):
        print(f"No encontré la lista 'favorite' en {state_path}", file=sys.stderr)
        sys.exit(1)

    n_antes = len(fav)
    fav_sorted = sorted(fav, key=lambda r: sortkey(r, meta))

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = f"{state_path}.bak-orden-{ts}"
    with open(backup, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    _chmod(backup)

    state["favorite"] = fav_sorted
    with open(state_path, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    _chmod(state_path)

    print(f"Favoritos reordenados: {n_antes} -> {len(fav_sorted)}")
    print(f"Backup: {backup}")
    print()
    print(f"{'CAL':<5}{'COST':<8}MODELO")
    for r in fav_sorted:
        nivel, cost = resolve(meta, r.get("providerID", ""), r.get("modelID", ""))
        iid = f"{r.get('providerID','')}/{r.get('modelID','')}"
        lvl = {1: "⭐🥇", 2: "🥈", 3: "🥉", 4: "🏅"}.get(nivel if nivel and nivel >= 1 else 0, "—")
        cs = "—" if cost is None else f"{cost:g}"
        print(f"{lvl:<5}{cs:<8}{iid}")


def _chmod(path):
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


if __name__ == "__main__":
    main()