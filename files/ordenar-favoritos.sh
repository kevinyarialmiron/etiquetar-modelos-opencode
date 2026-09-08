#!/usr/bin/env bash
# ordenar-favoritos.sh — reordena la lista de favoritos del picker /models de opencode
# para que muestre primero los mejores (calidad) y dentro de cada nivel el más caro,
# dejando los gratis al final. Solo afecta a la categoría Favoritos.
#
# FUENTES:
#   - ~/.local/state/opencode/model.json  (favorites/recent que usa el TUI)
#   - ~/.config/opencode/data/modelos.json (nivel + costo de los 496 modelos)
#
# NOTA: opencode mantiene una copia en memoria del estado; el reorden toma efecto
# definitivo al próximo arranque del TUI (o al hacer toggle de un favorito).
set -euo pipefail

STATE="$HOME/.local/state/opencode/model.json"
DATA="$HOME/.config/opencode/data/modelos.json"

if [[ ! -f "$STATE" ]]; then
  echo "No existe $STATE (¿opencode nunca corrió?)" >&2
  exit 1
fi
if [[ ! -f "$DATA" ]]; then
  echo "No existe $DATA. Regeneralo con: python3 ~/.config/opencode/bin/gen-modelos.py" >&2
  exit 1
fi

python3 - "$STATE" "$DATA" <<'PYEOF'
import json, os, sys, time, datetime

state_path, data_path = sys.argv[1], sys.argv[2]
state = json.load(open(state_path))

data = json.load(open(data_path))
meta = {}
for r in data["modelos"]:
    meta[r["id"]] = (r.get("nivel") or 0, r.get("cost_out"))

def key(r):
    iid = f"{r.get('providerID','')}/{r.get('modelID','')}"
    nivel, cost = meta.get(iid, (0, None))
    # 1) calidad ascendente pero sin-medalla (0) al final -> 99
    lvl = nivel if nivel and nivel >= 1 else 99
    # 2) dentro del mismo nivel, costo DESCENDENTE (más caro primero);
    #    costo desconocido (None) va al final
    c = cost if cost is not None else -1
    return (lvl, -c, r.get("modelID", ""))

fav = state.get("favorite", [])
n_antes = len(fav)
fav_sorted = sorted(fav, key=key)

ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
backup = f"{state_path}.bak-orden-{ts}"
with open(backup, "w") as f:
    json.dump(state, f, indent=2)
os.chmod(backup, 0o600)

state["favorite"] = fav_sorted
with open(state_path, "w") as f:
    json.dump(state, f, indent=2)
os.chmod(state_path, 0o600)

print(f"Favoritos reordenados: {n_antes} -> {len(fav_sorted)}")
print(f"Backup: {backup}")
print()
print(f"{'CAL':<5}{'COST':<8}MODELO")
for r in fav_sorted:
    iid = f"{r.get('providerID','')}/{r.get('modelID','')}"
    nivel, cost = meta.get(iid, (0, None))
    lvl = {1: "⭐🥇", 2: "🥈", 3: "🥉", 4: "🏅"}.get(nivel if nivel >= 1 else 0, "—")
    cs = "—" if cost is None else f"{cost:g}"
    print(f"{lvl:<5}{cs:<8}{iid}")
PYEOF