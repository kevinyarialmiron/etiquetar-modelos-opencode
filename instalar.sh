#!/usr/bin/env bash
# instalar.sh — instala el sistema de etiquetas de calidad+costo de modelos en una
# instancia de opencode (esta máquina u otra).
#
# Detecta automáticamente el caso "WSL con opencode de Windows" (binario en
# /mnt/c/...) y, en modo 'aplica', instala el opencode nativo de Linux antes de
# etiquetar, para que los tags vayan siempre a la config que el binario real lee.
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
warn() { echo "[instalar] AVISO: $*" >&2; }

# --- preflight --------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || err "necesitás python3 para generar las etiquetas. Instalalo y reintentá."

# --- detección de opencode --------------------------------------------------
# OC_KIND: linux | windows-wsl | missing
OPENCODE_BIN=""
OC_KIND=""
detect_opencode() {
  OPENCODE_BIN=""
  OC_KIND=""
  if [[ -x "$HOME/.opencode/bin/opencode" ]]; then
    OPENCODE_BIN="$HOME/.opencode/bin/opencode"
    OC_KIND="linux"
    return 0
  fi
  if command -v opencode >/dev/null 2>&1; then
    OPENCODE_BIN="$(command -v opencode)"
    case "$OPENCODE_BIN" in
      /mnt/*|/*/[a-zA-Z]/*) OC_KIND="windows-wsl" ;;
      *) OC_KIND="linux" ;;
    esac
    return 0
  fi
  OC_KIND="missing"
  return 1
}

# --- instalación del opencode NATIVO de Linux -------------------------------
# No depende de opencode.ai/install (que puede estar caído o "ver" el opencode
# de Windows y negarse). Baja el binario directo de releases de GitHub.
install_native_linux() {
  command -v curl >/dev/null 2>&1 || err "no hay curl para instalar opencode. Instalalo y reintentá."
  command -v tar >/dev/null 2>&1  || err "no hay tar para instalar opencode. Instalalo y reintentá."

  local arch ocarch
  arch="$(uname -m)"
  case "$arch" in
    x86_64)         ocarch="x64" ;;
    aarch64|arm64)  ocarch="arm64" ;;
    *) err "arquitectura no soportada: $arch" ;;
  esac

  echo "[instalar] instalando opencode nativo de Linux ($arch)..."
  local url="https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${ocarch}.tar.gz"
  local tmp; tmp="$(mktemp -d)"

  if ! curl -fsSL "$url" -o "$tmp/opencode.tar.gz"; then
    rm -rf "$tmp"
    err "falló descargar $url. Chequeá la conexión o instalá opencode manual: curl -fsSL https://opencode.ai/install | bash"
  fi
  if ! tar -xzf "$tmp/opencode.tar.gz" -C "$tmp"; then
    rm -rf "$tmp"
    err "falló descomprimir opencode (descarga corrupta). Reintentá."
  fi

  mkdir -p "$HOME/.opencode/bin"
  mv "$tmp/opencode" "$HOME/.opencode/bin/opencode"
  chmod 755 "$HOME/.opencode/bin/opencode"
  rm -rf "$tmp"

  if ! grep -Fqs "$HOME/.opencode/bin" "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# opencode\nexport PATH=%s:$PATH\n' "$HOME/.opencode/bin" >> "$HOME/.bashrc"
    echo "[instalar] agregado $HOME/.opencode/bin a \$PATH en ~/.bashrc"
  fi
  echo "[instalar] opencode nativo instalado: $HOME/.opencode/bin/opencode"
}

# --- resolución del binario de opencode -------------------------------------
detect_opencode

if [[ "$OC_KIND" == "windows-wsl" ]]; then
  warn "El opencode que se ve en el PATH es el de WINDOWS: $OPENCODE_BIN"
  echo "        En WSL ese binario lee la config de Windows (C:\\Users\\...), no ~/.config/opencode."
  if [[ -z "$DRY" && "$MODE" == "aplica" ]]; then
    echo "        Como querés aplicar las etiquetas, instalo el opencode NATIVO de Linux primero."
    echo "        No toca tu opencode de Windows (sigue intacto en PowerShell)."
    install_native_linux
    detect_opencode
  fi
elif [[ "$OC_KIND" == "missing" ]]; then
  if [[ -z "$DRY" && "$MODE" == "aplica" ]]; then
    echo "[instalar] no hay opencode; instalando el nativo de Linux..."
    install_native_linux
    detect_opencode
  fi
fi

if [[ "$OC_KIND" == "missing" ]]; then
  err "opencode no encontrado (ni ~/.opencode/bin/opencode ni en PATH)."
fi

echo "[instalar] opencode: $OPENCODE_BIN"
if [[ "$OC_KIND" == "windows-wsl" && -z "$DRY" ]]; then
  err "sigo viendo el opencode de Windows ($OPENCODE_BIN). Revisá manualmente: curl -fsSL https://opencode.ai/install | bash"
fi
if ! "$OPENCODE_BIN" --version >/dev/null 2>&1; then
  err "el binario $OPENCODE_BIN no se ejecuta. Revisalo a mano."
fi

# --- obtener archivos (local si es un clone; si no, descarga desde GitHub) --
files=(gen-modelos.py models-rank.json modelos.sh ordenar-favoritos.sh ordenar-favoritos.py commands-modelos.md probe-nvidia.py probe-proveedores.py nvidia-muertos.json watch-etiquetas.sh)
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
  "ordenar-favoritos.py:$BIN/ordenar-favoritos.py:755"
  "commands-modelos.md:$CMDS/modelos.md:644"
  "probe-nvidia.py:$BIN/probe-nvidia.py:755"
  "probe-proveedores.py:$BIN/probe-proveedores.py:755"
  "nvidia-muertos.json:$DATA/nvidia-muertos.json:644"
  "watch-etiquetas.sh:$BIN/watch-etiquetas.sh:755"
)

# cron del watcher automático (idempotente): regenera etiquetas cada 5 min si
# cambió auth.json/opencode.json/models-rank.json/nvidia-muertos.json.
# INSTALAR_NO_CRON=1 lo desactiva (útil en tests / entornos sin servicio cron).
install_watcher() {
  if [[ -n "${INSTALAR_NO_CRON:-}" ]]; then
    echo "[instalar] (watcher cron omitido por INSTALAR_NO_CRON=1)"
    return 0
  fi
  if ! command -v cron >/dev/null 2>&1 && ! command -v crond >/dev/null 2>&1; then
    echo "[instalar] (no hay cron; el watcher no se programa automáticamente)"
    return 0
  fi
  local line="*/5 * * * * $BIN/watch-etiquetas.sh >/dev/null 2>&1"
  if ! crontab -l 2>/dev/null | grep -Fq "$BIN/watch-etiquetas.sh"; then
    ( crontab -l 2>/dev/null || true; echo "$line" ) | crontab -
    echo "[instalar] watcher programado en cron (cada 5 min):"
    echo "          $line"
  else
    echo "[instalar] watcher ya estaba en cron"
  fi
}

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

  install_watcher

  if [[ $MODE == "aplica" ]]; then
    echo "[instalar] aplicando etiquetas a opencode.json (binario: $OPENCODE_BIN)..."
    OPENCODE_BIN="$OPENCODE_BIN" python3 "$BIN/gen-modelos.py" --apply
    echo "[instalar] LISTO. Reiniciá/recargá opencode para ver los cambios en /models."

    # reordenar Favoritos (solo si -y, o si es TTY y el usuario responde sí)
    if [[ -z "$NORD" ]]; then
      if [[ -n "$YES" ]]; then
        "$BIN/ordenar-favoritos.sh" \
          || echo "[nota] Favoritos no ordenados. Abrí opencode una vez y reintentá: $BIN/ordenar-favoritos.sh"
      elif [[ -t 0 && -t 1 ]]; then
        read -r -p "¿Reordenar también los Favoritos (calidad↓, precio↓)? [s/N] " resp
        if [[ "${resp,,}" == "s" || "${resp,,}" == "sí" || "${resp,,}" == "si" || "${resp,,}" == "y" ]]; then
          "$BIN/ordenar-favoritos.sh" \
            || echo "[nota] Favoritos no ordenados. Abrí opencode una vez y reintentá: $BIN/ordenar-favoritos.sh"
        fi
      fi
    fi
  else
    echo "[instalar] preview del dataset:"
    OPENCODE_BIN="$OPENCODE_BIN" python3 "$BIN/gen-modelos.py"
    echo
    echo "Ejecutá './instalar.sh aplica' para aplicar los nombres a opencode.json."
  fi
else
  echo "[instalar] DRY-RUN — no se escribió nada."
  for entry in "${plan[@]}"; do
    dst="${entry#*:}"; dst="${dst%%:*}"
    echo "  -> $dst"
  done
  [[ "$OC_KIND" == "windows-wsl" ]] && echo "  -> instalaría opencode nativo de Linux en ~/.opencode/bin/opencode"
  [[ $MODE == "aplica" ]] && echo "  -> $CONFIG (con backup .bak-etiquetas-<ts>)"
fi