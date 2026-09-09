#!/usr/bin/env bash
# Helpers compartidos de la suite de tests.
# Cada test corre en un HOME falso con un `opencode` shim descargado del catálogo
# fixo de tests/fixtures/verbose.txt, así NUNCA toca la config real del usuario.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
FIX="$TESTS_DIR/fixtures"
TMP="$TESTS_DIR/tmp"
ORIG_PATH="$PATH"

declare -i PASS=0
declare -i FAIL=0

new_home() {
  local name="$1"
  local h="$TMP/$name"
  rm -rf "$h"
  mkdir -p "$h/.config/opencode/data" "$h/.config/opencode/bin" \
           "$h/.config/opencode/commands" "$h/.local/share/opencode" \
           "$h/.local/state/opencode" "$h/bin"
  cp "$REPO_ROOT/files/gen-modelos.py"       "$h/.config/opencode/bin/gen-modelos.py"
  cp "$FIX/models-rank.json"                 "$h/.config/opencode/data/models-rank.json"
  cp "$FIX/nvidia-muertos.json"              "$h/.config/opencode/data/nvidia-muertos.json"
  cp "$FIX/opencode.json"                    "$h/.config/opencode/opencode.json"
  cp "$FIX/auth.json"                        "$h/.local/share/opencode/auth.json"
  cp "$TESTS_DIR/shim/opencode"              "$h/bin/opencode"
  chmod +x "$h/bin/opencode"
  echo "$h"
}

# setea el entorno al HOME falso
env_home() {
  export HOME="$1"
  export PATH="$1/bin:$ORIG_PATH"
  export XDG_CACHE_HOME="$HOME/.cache"
  export SHIM_VERBOSE_FILE="$FIX/verbose.txt"
  unset OPENCODE_BIN
}

run_gen() {
  python3 "$HOME/.config/opencode/bin/gen-modelos.py" "$@"
}

fail() {
  echo "  ✗ $*" >&2
  return 1
}