# PROMPT — instalación guiada en otra instancia de opencode

Copiá este bloque y pegáselo a una instancia de opencode en otra máquina
(después de descargar el repo, o directamente junto a `instalar.sh`/`instalar.ps1`
si ya lo tenés local).

> Si la otra instancia ya tiene el entorno instalado (`opencode`, `python3`),
> alcanza con que le pases este prompt y ella misma ejecute la instalación.

---

Configurá en esta instancia de opencode las **etiquetas de calidad y costo en el
selector de modelos (`/models`)**, igual que un repo público que existe para eso.

## Qué hacer

1. Si esta máquina tiene internet, ejecutá la instalación en una línea:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/kevinyarialmiron/etiquetar-modelos-opencode/main/instalar.sh | bash -s aplica -y
   ```

   - Detecta el binario de opencode (PATH, `~/.opencode/bin/opencode` o app de
     escritorio Windows) y si en WSL ve el de Windows, instala el nativo de Linux
   - Descarga los scripts desde el repo y los copia a `~/.config/opencode/{bin,data,commands}`
   - Hace backup de `opencode.json` (`.bak-etiquetas-<fecha>`)
   - Genera `data/modelos.json` y aplica los nombres a `provider.*.models.*.name`
   - `-y` reordena además la pestaña Favoritos sin preguntar

   En Windows: corré el instalador PowerShell (`instalar.ps1 -aplica -yes`), que
   detecta opencode, Python, baja con retry + fallback CDN y setea `OPENCODE_BIN`
   y `PYTHONIOENCODING=utf-8` (los emojis no codifican en cp1252).

2. Verificás: `opencode models` no rompe, y en el TUI `/models` se ven las
   etiquetas con la escala.

Si por algún motivo no se pudiera descargar el repo, implementá el criterio
descrito abajo desde cero (también válido).

## Criterio exacto

**Escala de costo** (precio de *output* por 1M tokens, USD):
- `$0` → 🌱 (gratis) · `$0.01–$0.99` → 🪙 (centavos)
- `$1–2` → ❶ · `$2–3` → ❷ · `$3–4` → ❸ · `$4–5` → ❹ · `$5–6` → ❺❗ · … · `≥$10` → ❿❗
- Todo precio >$5 lleva ❗.

**Escala de calidad** (hasta 3 emojis por nombre):
- Nivel 1 → `⭐🥇<costo> Nombre` · Nivel 2 → `🥈<costo> Nombre` · Nivel 3 → `🥉<costo> Nombre`
- Nivel 4 → `🏅<costo> Nombre` · Sin medalla (evitar) → `<costo> Nombre`.

**Fuente**: `opencode models --verbose` (IDs visibles + costos nativos por
proveedor; ollama siempre gratis).

**Reglas de calidad**: `~/.config/opencode/data/models-rank.json` con `override`
(asignaciones por ID) y `niveles` (regex por nivel). Las reglas tienen prioridad
sobre las medallas ya presentes en los nombres del config (esas quedan como
fallback para modelos sin regla).

**Comando `/modelos`**: `bin/modelos.sh` + `commands/modelos.md` (lista por
proveedor/calidad/precio/contexto).

**Orden de Favoritos** (`bin/ordenar-favoritos.py`, wrapper `ordenar-favoritos.sh`):
solo la pestaña Favoritos, calidad ↓ y dentro de cada nivel precio ↓ (gratis al
final); escribe `~/.local/state/opencode/model.json` con backup, sin tocar
`recent` ni `variant`. Mapeo tolerante: si un id no está en `modelos.json`, lo
busca por prefijo de proveedor/sufijo de modelo antes de mandarlo al fondo.

**Metodología / transparencia**: `METODOLOGIA.md` explica el baremo (curado, no
benchmark), la fuente del costo (catálogo nativo de opencode) y Windows.

## Reglas de oro
- No aplicar el orden de favoritos con el TUI abierto (la copia en memoria pisa
  el cambio); tomá efecto al próximo arranque.
- `gen-modelos.py --apply` es idempotente: reemplaza prefijos, no los duplica.
- No tocar tokens/config de auth; solo la entrada `name` de cada modelo.