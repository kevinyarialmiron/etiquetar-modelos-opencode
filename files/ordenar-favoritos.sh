#!/usr/bin/env bash
# ordenar-favoritos.sh — reordena la pestaña Favoritos del picker /models de opencode
# (mejores arriba, dentro del mismo nivel el más caro primero, gratis al final).
# Solo afecta a la categoría Favoritos. Wrapper del .py portable (Linux/macOS/Windows).
#
# FUENTES:
#   - ~/.local/state/opencode/model.json  (favorites/recent que usa el TUI)
#   - ~/.config/opencode/data/modelos.json (nivel + costo de los modelos)
#
# NOTA: opencode mantiene una copia en memoria del estado; el reorden toma efecto
# definitivo al próximo arranque del TUI (al correrlo con el TUI abierto, la copia
# en memoria puede pisar el cambio al salir).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="$HOME/.local/state/opencode/model.json"
DATA="$HOME/.config/opencode/data/modelos.json"

if [[ ! -f "$STATE" ]]; then
  echo "No existe $STATE (¿opencode nunca corrió?)" >&2
  exit 1
fi
if [[ ! -f "$DATA" ]]; then
  echo "No existe $DATA. Regeneralo con: python3 ${DIR}/gen-modelos.py" >&2
  exit 1
fi

exec python3 "$DIR/ordenar-favoritos.py" "$STATE" "$DATA"