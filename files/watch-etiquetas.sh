#!/usr/bin/env bash
# Watcher de etiquetado automático (vía cron/systemd).
# Regenera las etiquetas sólo si cambió algo relevante: auth.json (proveedores
# con key/login), opencode.json (modelos/etiquetas), models-rank.json (reglas)
# o gen-modelos.py. Idempotente: si nada cambió, no toca nada.
#
# Instalar: crontab -e ->  */5 * * * *  ~/.config/opencode/bin/watch-etiquetas.sh
# (o copiarlo a un dir del PATH y apuntar la línea ahí).
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
BIN_DIR="$CONFIG_DIR/bin"
DATA_DIR="$CONFIG_DIR/data"
GEN="$BIN_DIR/gen-modelos.py"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode-etiquetas"
SNAP_DIR="$CACHE_DIR/snap"
LOG="$CACHE_DIR/watch.log"

mkdir -p "$SNAP_DIR" "$CACHE_DIR" "$DATA_DIR"

# huella de los archivos que disparan regeneración
snap() {
    local f
    for f in \
        "$HOME/.local/share/opencode/auth.json" \
        "$CONFIG_DIR/opencode.json" \
        "$DATA_DIR/models-rank.json" \
        "$GEN" \
        "$DATA_DIR/nvidia-muertos.json"; do
        if [ -f "$f" ]; then
            sha256sum "$f" 2>/dev/null
        fi
    done | sort | sha256sum
}

lock() {
    exec 9>"$CACHE_DIR/watch.lock"
    if ! flock -n 9; then
        exit 0
    fi
}

[ -x "$GEN" ] || exit 0

if [ "${1:-}" = "--force" ]; then
    prev=""
else
    prev=""
    if [ -f "$SNAP_DIR/estado" ]; then
        prev="$(cat "$SNAP_DIR/estado" 2>/dev/null || true)"
    fi
fi

cur="$(snap)"

if [ "$prev" != "$cur" ]; then
    lock
    echo "$(date -Is) cambio detectado, regenerando..." >> "$LOG"
    if python3 "$GEN" --apply >> "$LOG" 2>&1; then
        echo "$cur" > "$SNAP_DIR/estado"
        echo "$(date -Is) ok" >> "$LOG"
    else
        echo "$(date -Is) FALLO (no se marca estado; reintenta el próximo ciclo)" >> "$LOG"
    fi
fi
exit 0