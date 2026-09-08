#!/usr/bin/env bash
# instalar.sh — instala el sistema de etiquetas de calidad+costo de modelos en una
# instancia de opencode (esta máquina u otra).
#
# Uso:
#   ./instalar.sh                instalación con preview (no toca opencode.json)
#   ./instalar.sh aplica         aplica los nombres a opencode.json (interactivo)
#   ./instalar.sh aplica -y      aplica y reordena Favoritos sin preguntar
#   ./instalar.sh aplica -n      aplica sin reordenar Favoritos
#   ./instalar.sh --dry-run      muestra qué haría sin escribir nada
#
# Instalación remota (una línea):
#   curl -fsSL <RAW_URL>/instalar.sh | bash -s aplica -y
#
set -euo pipefail

# --- configuración del repo remoto (para instalación por pipe) -------------
REPO_OWNER="kevinyarialmiron"
REPO_NAME="etiquetar-modelos-opencode"
BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH"

PROG="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CFG="$HOME/.config/opencode"
BIN="$CFG/bin"
DATA="$CFG/data"
CMDS="$CFG/commands"
CONFIG="$CFG/opencode.json"

DRY=""
MODE="preview"      # preview | aplica
YES=""
NORD=""

for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    aplica) MODE="aplica" ;;
    -y|--yes) YES=1 ;;
    -n|--no-favoritos) NORD=1 ;;
  esac
done

err() { echo "[instalar] ERROR: $*" >&2; exit 1; }

# --- preflight --------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || err "necesitás python3 para generar las etiquetas. Instalalo y reintentá."

OPENCODE_BIN=""
if [[ -x "$HOME/.opencode/bin/opencode" ]]; then
  OPENCODE_BIN="$HOME/.opencode/bin/opencode"
elif command -v opencode >/dev/null 2>&1; then
  OPENCODE_BIN="$(command -v opencode)"
else
  err "opencode no encontrado (ni ~/.opencode/bin/opencode ni en PATH). Instalalo primero: curl -fsSL https://opencode.ai/install | bash"
fi
echo "[instalar] opencode: $OPENCODE_BIN"

# --- obtener archivos (local si es un clone; si no, descarga desde GitHub) --
files=(gen-modelos.py models-rank.json modelos.sh ordenar-favoritos.sh commands-modelos.md)
SRC="$SCRIPT_DIR/files"
if [[ ! -d "$SRC" ]]; then
  command -v curl >/dev/null 2>&1 || err "no encuentro los archivos localmente y no hay curl para descargarlos. Cloná el repo o instalá curl."
  TMPDIR_OC="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR_OC"' EXIT
  SRC="$TMPDIR_OC/files"
  mkdir -p "$SRC"
  echo "[instalar] descargando archivos desde $RAW_BASE/files/"
  for f in "${files[@]}"; do
    curl -fsSL "$RAW_BASE/files/$f" -o "$SRC/$f" \
      || err "falló descargar $f desde $RAW_BASE (¿existe el repo? $REPO_OWNER/$REPO_NAME)"
  done
fi
[[ -f "$SRC/gen-modelos.py" ]] || err "falta gen-modelos.py en $SRC"

# --- plan de copias ---------------------------------------------------------
mkdir -p "$BIN" "$DATA" "$CMDS"
plan=(
  "gen-modelos.py:$BIN/gen-modelos.py:755"
  "models-rank.json:$DATA/models-rank.json:644"
  "modelos.sh:$BIN/modelos.sh:755"
  "ordenar-favoritos.sh:$BIN/ordenar-favoritos.sh:755"
  "commands-modelos.md:$CMDS/modelos.md:644"
)

echo "[instalar] modo: $MODE"
if [[ -z "$DRY" ]]; then
  for entry in "${plan[@]}"; do
    src="${entry%%:*}"
    rest="${entry#*:}"
    dst="${rest%%:*}"
    mode="${rest##*:}"
    cp "$SRC/$src" "$dst"
    chmod "$mode" "$dst"
    echo "  copiado: $dst"
  done

  if [[ -f "$CONFIG" ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    cp "$CONFIG" "$CONFIG.bak-etiquetas-$ts"
    echo "[instalar] backup: $CONFIG.bak-etiquetas-$ts"
  fi

  if [[ $MODE == "aplica" ]]; then
    echo "[instalar] aplicando etiquetas a opencode.json..."
    python3 "$BIN/gen-modelos.py" --apply
    echo "[instalar] LISTO. Reiniciá/recargá opencode para ver los cambios en /models."

    # reordenar Favoritos (solo si -y, o si es TTY y el usuario responde sí)
    if [[ -z "$NORD" ]]; then
      if [[ -n "$YES" ]]; then
        "$BIN/ordenar-favoritos.sh" || echo "[warn] no se pudo reordenar favoritos"
      elif [[ -t 0 && -t 1 ]]; then
        read -r -p "¿Reordenar también los Favoritos (calidad↓, precio↓)? [s/N] " resp
        if [[ "${resp,,}" == "s" || "${resp,,}" == "sí" || "${resp,,}" == "si" || "${resp,,}" == "y" ]]; then
          "$BIN/ordenar-favoritos.sh" || echo "[warn] no se pudo reordenar favoritos"
        fi
      fi
    fi
  else
    echo "[instalar] preview del dataset:"
    python3 "$BIN/gen-modelos.py"
    echo
    echo "Ejecutá './instalar.sh aplica' para aplicar los nombres a opencode.json."
  fi
else
  echo "[instalar] DRY-RUN — no se escribió nada."
  for entry in "${plan[@]}"; do
    dst="${entry#*:}"; dst="${dst%%:*}"
    echo "  -> $dst"
  done
  [[ $MODE == "aplica" ]] && echo "  -> $CONFIG (con backup .bak-etiquetas-<ts>)"
fi