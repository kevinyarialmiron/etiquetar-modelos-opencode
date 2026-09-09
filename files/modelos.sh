#!/usr/bin/env bash
# /modelos — lista modelos de opencode con etiquetas de calidad y costo.
# Uso:
#   /modelos                       todos, ordenados por calidad (default)
#   /modelos barato                todos, ordenados por precio
#   /modelos ctx                   todos, ordenados por contexto
#   /modelos <proveedor>           un proveedor, por calidad
#   /modelos <proveedor> barato    un proveedor, por precio
set -euo pipefail

DATA="$HOME/.config/opencode/data/modelos.json"
if [[ ! -f "$DATA" ]]; then
  echo "Falta $DATA. Regeneralo con: python3 ~/.config/opencode/bin/gen-modelos.py" >&2
  exit 1
fi

PROV_ARG=""
SORT="calidad"
for a in "$@"; do
  case "${a,,}" in
    barato|precio|precio|cost|costo) SORT="precio" ;;
    ctx|contexto) SORT="ctx" ;;
    calidad|confiable|reliabilidad) SORT="calidad" ;;
    *) PROV_ARG="$a" ;;
  esac
done

python3 - "$DATA" "$PROV_ARG" "$SORT" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
prov_arg = sys.argv[2].lower() if len(sys.argv) > 2 else ""
sort = sys.argv[3] if len(sys.argv) > 3 else "calidad"

rows = data["modelos"]
if prov_arg:
    rows = [r for r in rows if r["provider"] == prov_arg]
if sort == "precio":
    rows = sorted(rows, key=lambda r: (r["cost_out"] is None, r["cost_out"] if r["cost_out"] is not None else 1e9))
elif sort == "ctx":
    rows = sorted(rows, key=lambda r: (-(r["contexto"] or 0)))
else:
    rows = sorted(rows, key=lambda r: (r["nivel"] if r["nivel"] else 99, r["cost_out"] if r["cost_out"] is not None else 1e9))

# resumen por nivel
from collections import Counter
niv = Counter(r["nivel"] for r in rows)
print(f"== /modelos ({len(rows)} modelos) ==")
print(f"   ⭐🥇={niv[1]}  🥈={niv[2]}  🥉={niv[3]}  🏅={niv[4]}  sin-medalla={niv[0]}")
print()
print(f"{'NIVEL':<6}{'TIPO':<8}{'PROVEEDOR':<12}{'COSTO($/1M)':<12}{'CTX':<10}MODELO")
for r in rows:
    costo = "—" if r["cost_out"] is None else f"{r['cost_out']:g}"
    ctx = "—" if not r["contexto"] else f"{r['contexto']:,}"
    lvl = {1:"⭐🥇",2:"🥈",3:"🥉",4:"🏅"}.get(r["nivel"],"—")
    tipo = {"chat":"chat","embed":"🧩","imagen":"🖼️","audio":"🎙️"}.get(r.get("tipo"),"—")
    print(f"{lvl:<6}{tipo:<8}{r['provider']:<12}{costo:<12}{ctx:<10}{r['name']}")
EOF