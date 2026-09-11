#!/usr/bin/env bash
# Suite de tests end-to-end del sistema de etiquetado de modelos.
# Todo corre contra HOME falsos + shim de opencode: no toca config real ni red.
#
#   ./tests/run.sh            corre la suite completa
#   ./tests/run.sh t_gen...   corre un test puntual
#
# Exit 0 = todo verde, exit 1 = hay fallos (usar como pre-commit).
set -uo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

# kill caches de python previas en files/ (py_compile) y tmp
rm -rf "$REPO_ROOT/files/__pycache__" "$TMP"
mkdir -p "$TMP"

# ----------------------------------------------------------------------------+
# T1. estáticos: sintaxis shell/python, JSON válidos, parseo PowerShell
# ----------------------------------------------------------------------------+
t_estaticos() {
  local f
  for f in "$REPO_ROOT"/instalar.sh "$REPO_ROOT"/files/*.sh; do
    bash -n "$f" || fail "bash -n: $f"
  done
  python3 -m py_compile \
    "$REPO_ROOT/files/gen-modelos.py" \
    "$REPO_ROOT/files/probe-nvidia.py" \
    "$REPO_ROOT/files/probe-proveedores.py" \
    "$REPO_ROOT/files/ordenar-favoritos.py" || fail "py_compile"
  python3 - "$REPO_ROOT" <<'PY' || fail "JSON inválido"
import json, os, sys
root = sys.argv[1]
for rel in ("files/models-rank.json", "files/nvidia-muertos.json", "tests/fixtures/models-rank.json",
            "tests/fixtures/nvidia-muertos.json", "tests/fixtures/opencode.json", "tests/fixtures/auth.json"):
    json.load(open(os.path.join(root, rel), encoding="utf-8"))
PY
  # Validamos que instalar.ps1 siga siendo sintácticamente válido. Buscamos el
  # PowerShell disponible: `pwsh` (el oficial moderno, presente en CI/runner), o
  # `powershell.exe` (la ruta de WSL, /mnt/c/...). Si no hay ninguno, se salta.
  local psbin=""
  if command -v pwsh >/dev/null 2>&1; then
    psbin="$(command -v pwsh)"
  elif command -v powershell >/dev/null 2>&1; then
    psbin="$(command -v powershell)"
  elif [ -f "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
    psbin="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  fi
  if [ -n "$psbin" ]; then
    local pscp="$TMP/check-parse.ps1"
    local wpath
    cp "$REPO_ROOT/instalar.ps1" "$pscp"
    case "$psbin" in
      /mnt/*) wpath="$(cygpath -w "$pscp" 2>/dev/null || echo "$pscp")" ;;
      *) wpath="$pscp" ;;
    esac
    "$psbin" -NoProfile -Command \
      "[void][System.Management.Automation.Language.Parser]::ParseFile('$wpath',[ref]\$null,[ref]\$null)" \
      || fail "parseo PS de instalar.ps1 (via $psbin)"
  else
    echo "  (sin pwsh/powershell; parseo PS salteado)"
  fi
  return 0
}

# ----------------------------------------------------------------------------+
# T2. gen-modelos: rankings, costos, tipos y ocultamiento
# ----------------------------------------------------------------------------+
t_gen() {
  local h; h=$(new_home gen); env_home "$h"
  run_gen >/dev/null 2>&1 || fail "gen-modelos falló"
  python3 - <<'PY' || fail "aserciones del dataset fallaron (ver arriba)"
import json, os
rows = json.load(open(os.path.expanduser("~/.config/opencode/data/modelos.json")))["modelos"]
ids = {r["id"]: r for r in rows}

muertos = ["nvidia/nvidia/nv-embed-v1", "nvidia/nvidia/nemotron-mini-4b-instruct",
           "nvidia/nvidia/flux_1", "nvidia/openai/whisper-large-v3",
           "nvidia/nvidia/studiovoice", "openrouter/mistralai/mistral-large-3.5"]
for mid in muertos:
    assert mid not in ids, f"{mid} debió ocultarse pero está en el dataset"

assert len(rows) == 18, f"esperaba 18 modelos visibles, hay {len(rows)}"

def n(mid): return ids[mid]["name"]
def tipo(mid): return ids[mid]["tipo"]

assert n("openrouter/anthropic/claude-opus-4.0") == "⭐🥇❿❗ Claude Opus 4.0", n("openrouter/anthropic/claude-opus-4.0")
assert n("openrouter/anthropic/claude-sonnet-4.0") == "🥈❸ Claude Sonnet 4.0", n("openrouter/anthropic/claude-sonnet-4.0")
assert n("openrouter/deepseek/deepseek-v4-pro") == "⭐🥇🪙 DeepSeek V4 Pro", n("openrouter/deepseek/deepseek-v4-pro")
assert n("openrouter/mistralai/mistral-small-3.2") == "🥈🪙 Mistral Small 3.2", "fallback de medalla"
assert n("openrouter/openai/gpt-5-nano") == "🥈🌱 GPT 5 Nano", n("openrouter/openai/gpt-5-nano")
assert n("openrouter/deepseek/deepseek-v3.1-terminus") == "🥈🪙 DeepSeek V3.1 Terminus", n("openrouter/deepseek/deepseek-v3.1-terminus")
assert n("google/gemini-3-flash-preview") == "🥉❷ Gemini 3 Flash Preview", n("google/gemini-3-flash-preview")
assert n("google/gemini-2.5-pro") == "🥉❺❗ Gemini 2.5 Pro", n("google/gemini-2.5-pro")
assert n("google/gemini-2.5-flash-preview-tts") == "🎙️❿❗ Gemini 2.5 Flash Preview TTS", "tag audio entre medalla y costo"
assert n("google/gemini-3-pro-image") == "🖼️❻❗ Gemini 3 Pro Image", "tag imagen"
assert n("nvidia/moonshotai/kimi-k3") == "⭐🥇🌱 Kimi K3", n("nvidia/moonshotai/kimi-k3")
assert n("nvidia/nvidia/nemotron-3.5-lightning-30b-a3b") == "🥉🌱 Nemotron 3.5 Lightning 30B A3B", n("nvidia/nvidia/nemotron-3.5-lightning-30b-a3b")
assert n("nvidia/nvidia/llama-nemotron-embed-vl-1b-v2") == "🧩🌱 llama-nemotron-embed-vl-1b-v2", "tag embed"
assert n("opencode/nemotron-3-ultra-free") == "🏅🌱 Nemotron 3 Ultra Free", n("opencode/nemotron-3-ultra-free")

assert tipo("google/gemini-3-pro-image") == "imagen"
assert tipo("google/gemini-2.5-flash-preview-tts") == "audio"
assert tipo("nvidia/nvidia/llama-nemotron-embed-vl-1b-v2") == "embed"
assert tipo("openrouter/meta/llama-4-maverick") == "chat"
assert tipo("nvidia/moonshotai/kimi-k3") == "chat"
PY
  return 0
}

# ----------------------------------------------------------------------------+
# T3. --apply: escribe config; los muertos se marcan SIEMPRE 💀 (aun sin entrada
#     previa) y quedan fuera del dataset
# ----------------------------------------------------------------------------+
t_apply_ocultos() {
  local h; h=$(new_home apply); env_home "$h"
  run_gen --apply >/dev/null 2>&1 || fail "apply falló"
  python3 - <<'PY' || fail "apply de ocultos falló"
import json, os
cfg = json.load(open(os.path.expanduser("~/.config/opencode/opencode.json")))
nm = cfg["provider"]["nvidia"]["models"]
# muerto que ya tenia etiqueta -> calavera
assert nm["nvidia/nemotron-mini-4b-instruct"]["name"] == "💀 Nemotron Mini 4B", nm["nvidia/nemotron-mini-4b-instruct"]["name"]
# muerto SIN entrada previa -> tambien se crea marcado calavera (no queda invisible)
assert nm["nvidia/nv-embed-v1"]["name"] == "💀 Ingest E5 Mistral", nm["nvidia/nv-embed-v1"]["name"]
assert nm["nvidia/openai/whisper-large-v3"]["name"] == "💀 Whisper Large V3", nm["nvidia/openai/whisper-large-v3"]["name"]
assert cfg["provider"]["openrouter"]["models"]["anthropic/claude-opus-4.0"]["name"] == "⭐🥇❿❗ Claude Opus 4.0"
# los base-name originales se conservan (strip idempotente)
assert cfg["provider"]["openrouter"]["models"]["mistralai/mistral-small-3.2"]["name"] == "🥈🪙 Mistral Small 3.2"
PY
  return 0
}

# ----------------------------------------------------------------------------+
# T4. idempotencia: dos applies seguidos no cambian config ni dataset
# ----------------------------------------------------------------------------+
t_idempotencia() {
  local h; h=$(new_home idem); env_home "$h"
  run_gen --apply >/dev/null 2>&1 || fail "apply #1 falló"
  local c1 d1 c2 d2
  c1=$(sha256sum "$HOME/.config/opencode/opencode.json" | cut -d' ' -f1)
  d1=$(sha256sum "$HOME/.config/opencode/data/modelos.json" | cut -d' ' -f1)
  run_gen --apply >/dev/null 2>&1 || fail "apply #2 falló"
  c2=$(sha256sum "$HOME/.config/opencode/opencode.json" | cut -d' ' -f1)
  d2=$(sha256sum "$HOME/.config/opencode/data/modelos.json" | cut -d' ' -f1)
  [ "$c1" = "$c2" ] || fail "opencode.json NO es idempotente"
  [ "$d1" = "$d2" ] || fail "modelos.json NO es idempotente"
  return 0
}

# ----------------------------------------------------------------------------+
# T5. orden de Favoritos (calidad asc, costo desc dentro de nivel, modelID)
# ----------------------------------------------------------------------------+
t_favoritos() {
  local h; h=$(new_home fav); env_home "$h"
  run_gen --apply >/dev/null 2>&1 || fail "apply falló"
  cp "$FIX/state.json" "$HOME/.local/state/opencode/model.json"
  python3 "$REPO_ROOT/files/ordenar-favoritos.py" \
    "$HOME/.local/state/opencode/model.json" \
    "$HOME/.config/opencode/data/modelos.json" >/dev/null 2>&1 || fail "ordenar-favoritos falló"
  python3 - <<'PY' || fail "orden de favoritos incorrecto"
import json, os
st = json.load(open(os.path.expanduser("~/.local/state/opencode/model.json")))
ids = [(f["providerID"], f["modelID"]) for f in st["favorite"]]
esperado = [
    ("openrouter", "anthropic/claude-opus-4.0"),
    ("openrouter", "deepseek/deepseek-v4-pro"),
    ("nvidia", "moonshotai/kimi-k3"),
    ("openrouter", "anthropic/claude-sonnet-4.0"),
    ("openrouter", "openai/gpt-5-nano"),
    ("google", "gemini-3-flash-preview"),
]
assert ids == esperado, f"\nobtenido: {ids}\nesperado: {esperado}"
assert os.path.exists(os.path.expanduser("~/.local/state/opencode/model.json.bak-orden-") + "" or next(
    (f for f in os.listdir(os.path.expanduser("~/.local/state/opencode")) if f.startswith("model.json.bak-orden-")), None)), "sin backup"
PY
  return 0
}

# ----------------------------------------------------------------------------+
# T6. watcher: regenera al primer arranque, NO al estar todo igual, y SÍ al
#     cambiar auth.json
# ----------------------------------------------------------------------------+
t_watch() {
  local h; h=$(new_home watch); env_home "$h"
  local w="$REPO_ROOT/files/watch-etiquetas.sh"
  local snap="$HOME/.cache/opencode-etiquetas/snap/estado"

  "$w" >/dev/null 2>&1 || fail "watch #1 falló"
  [ -f "$snap" ] || fail "watch #1 no generó estado"
  grep -q "⭐🥇" "$HOME/.config/opencode/opencode.json" || fail "watch #1 no aplicó etiquetas"

  local s1
  s1=$(cat "$snap")
  "$w" >/dev/null 2>&1 || fail "watch #2 falló"
  local s2; s2=$(cat "$snap")
  [ "$s1" = "$s2" ] || fail "watch regeneró sin que cambiara nada"

  echo '{"demo":"cambio"}' >> "$HOME/.local/share/opencode/auth.json"
  "$w" >/dev/null 2>&1 || fail "watch #3 falló"
  local s3; s3=$(cat "$snap")
  [ "$s1" != "$s3" ] || fail "watch no detectó el cambio en auth.json"

  echo "  (log: $HOME/.cache/opencode-etiquetas/watch.log)"
  return 0
}

# ----------------------------------------------------------------------------+
# T7. instalador en HOME falso: copia, backup, nombres y 💀
# ----------------------------------------------------------------------------+
t_instalador() {
  local h; h=$(new_home install); env_home "$h"
  export INSTALAR_NO_CRON=1
  (cd "$REPO_ROOT" && bash ./instalar.sh aplica -n) >/dev/null 2>&1 || fail "instalar.sh falló"
  local f
  for f in probe-nvidia.py watch-etiquetas.sh modelos.sh ordenar-favoritos.py commands-modelos.md; do
    [ -f "$HOME/.config/opencode/bin/$f" ] || [ -f "$HOME/.config/opencode/commands/$f" ] \
      || fail "no copió $f"
  done
  [ -f "$HOME/.config/opencode/data/nvidia-muertos.json" ] || fail "no copió nvidia-muertos.json"
  [ -f "$HOME/.config/opencode/data/modelos.json" ] || fail "no generó data/modelos.json"
  grep -q "⭐🥇❿❗ Claude Opus 4.0" "$HOME/.config/opencode/opencode.json" || fail "no aplicó nombre principal"
  grep -q "💀 Nemotron Mini 4B" "$HOME/.config/opencode/opencode.json" || fail "no marcó muerto 💀"
  ls "$HOME/.config/opencode/opencode.json.bak-etiquetas-"* >/dev/null 2>&1 || fail "no hizo backup"

  bash "$HOME/.config/opencode/bin/modelos.sh" >/dev/null 2>&1 || fail "modelos.sh falló"
  return 0
}

# ----------------------------------------------------------------------------+
# T8. comando /modelos en el HOME de gen (columna TIPO)
# ----------------------------------------------------------------------------+
t_modelos_cmd() {
  local h; h=$(new_home cmd); env_home "$h"
  run_gen --apply >/dev/null 2>&1 || fail "apply falló"
  local out
  out=$(bash "$HOME/.config/opencode/bin/modelos.sh" 2>&1) || fail "modelos.sh falló"
  echo "$out" | grep -q "== /modelos (18 modelos) ==" || fail "contador de modelos difiere"
  echo "$out" | grep -q "TIPO" || fail "falta columna TIPO"
  echo "$out" | grep -q "🎙️" || fail "no muestra tipo audio"
  echo "$out" | grep -q "🧩" || fail "no muestra tipo embed"
  return 0
}

# ----------------------------------------------------------------------------+
# T9. muertos multi-proveedor (probe-*.json): 4xx definitivo oculta, "timeout"
#     (dudoso) NO oculta ni marca 💀
# ----------------------------------------------------------------------------+
t_muertos_multiprov() {
  local h; h=$(new_home multiprov); env_home "$h"
  cp "$REPO_ROOT/tests/fixtures/probe-openrouter.json" \
     "$HOME/.config/opencode/data/probe-openrouter.json"
  run_gen --apply >/dev/null 2>&1 || fail "apply falló"
  python3 - <<'PY' || fail "muertos multi-proveedor incorrectos"
import json, os
cfg = json.load(open(os.path.expanduser("~/.config/opencode/opencode.json")))
orms = cfg["provider"]["openrouter"]["models"]
# 4xx definitivo -> 💀
assert orms["deepseek/deepseek-v3.1-terminus"]["name"] == "💀 DeepSeek V3.1 Terminus", \
    orms["deepseek/deepseek-v3.1-terminus"]["name"]
# timeout (dudoso) -> NUNCA se oculta ni se marca 💀
assert not orms["meta/llama-4-maverick"]["name"].startswith("💀"), \
    orms["meta/llama-4-maverick"]["name"]

rows = json.load(open(os.path.expanduser("~/.config/opencode/data/modelos.json")))["modelos"]
ids = {r["id"] for r in rows}
assert "openrouter/deepseek/deepseek-v3.1-terminus" not in ids, "el 404 debió ocultarse"
assert "openrouter/meta/llama-4-maverick" in ids, "el timeout NO debió ocultarse"
PY
  return 0
}

# ----------------------------------------------------------------------------+
# T10. costos curados: proveedor sin precio en el catálogo (ollama-cloud, que
#      trae $0) usa el costo de models-rank.json; el aviso de pico (🕒🔥x2) se
#      agrega y NO se duplica en un segundo apply
# ----------------------------------------------------------------------------+
t_costos_curados() {
  local h; h=$(new_home costos); env_home "$h"
  export SHIM_VERBOSE_FILE="$FIX/verbose-ollama-cloud.txt"
  run_gen --apply >/dev/null 2>&1 || fail "apply #1 falló"
  python3 - <<'PY' || fail "costos curados incorrectos"
import json, os
cfg = json.load(open(os.path.expanduser("~/.config/opencode/opencode.json")))
cm = cfg["provider"]["ollama-cloud"]["models"]
# kimi-k3 $15 -> ❿❗ (NO 🌱)
assert cm["kimi-k3"]["name"] == "⭐🥇❿❗ kimi-k3", cm["kimi-k3"]["name"]
# deepseek-v4-pro $1.98 + peak -> ❶ + aviso (🕒🔥x2)
assert cm["deepseek-v4-pro"]["name"] == "🥈❶ deepseek-v4-pro (🕒🔥x2)", cm["deepseek-v4-pro"]["name"]
rows = {r["id"]: r for r in json.load(open(os.path.expanduser("~/.config/opencode/data/modelos.json")))["modelos"]}
assert rows["ollama-cloud/kimi-k3"]["cost_out"] == 15.0
assert rows["ollama-cloud/deepseek-v4-pro"]["peak"] is True
PY
  run_gen --apply >/dev/null 2>&1 || fail "apply #2 falló"
  python3 - <<'PY' || fail "el aviso de pico se duplicó"
import json, os
cm = json.load(open(os.path.expanduser("~/.config/opencode/opencode.json")))["provider"]["ollama-cloud"]["models"]
n = cm["deepseek-v4-pro"]["name"]
assert n.count("(🕒🔥x2)") == 1, n
PY
  return 0
}

# ----------------------------------------------------------------------------+
# runner
# ----------------------------------------------------------------------------+
T_LIST="$@"
if [ "$#" -eq 0 ]; then
  T_LIST="t_estaticos t_gen t_apply_ocultos t_idempotencia t_favoritos t_watch t_instalador t_modelos_cmd t_muertos_multiprov t_costos_curados"
fi

for tname in $T_LIST; do
  out="$TMP/$tname.out"
  : > "$out"
  if ( "$tname" ) >"$out" 2>&1; then
    PASS+=1
    echo "PASS  $tname"
  else
    FAIL+=1
    echo "FAIL  $tname"
    sed 's/^/      /' "$out"
  fi
  rm -f "$out"
done

echo
echo "===== $PASS pasan, $FAIL fallan ====="
rm -rf "$REPO_ROOT/files/__pycache__"
[ "$FAIL" -eq 0 ]