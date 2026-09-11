# Etiquetar Modelos de OpenCode

Etiqueta automáticamente **todos los modelos** del selector `/models` de [OpenCode](https://opencode.ai)
(los ~500 visibles: openrouter, opencode, opencode-go, google, deepseek, ollama,
nvidia y cualquier proveedor que tu instancia autentique)
con su **calidad** y su **costo por 1M de tokens**, y ordena la pestaña **Favoritos**
por calidad y precio. Con dos comandos tenés el picker legible de una vez.

Funciona en **Linux, macOS, WSL y Windows** (terminal y app de escritorio).

## Qué hace

- **~500 modelos** etiquetados al instante (todo lo que tu opencode "ve").
- **Calidad**: ⭐🥇 nivel 1 (más confiable) · 🥈 nivel 2 · 🥉 nivel 3 · 🏅 nivel 4 · *sin medalla = evitar*.
- **Costo** (salida por 1M tokens): 🌱 gratis · 🪙 centavos · ❶ $1-2 · ❷ $2-3 · … · ❺❗ $5-6 · ❿❗ ≥$10.
  Si un modelo cobra distinto en hora pico, se agrega el aviso `(🕒🔥x2)` (el doble).
- **Tipo**: 🧩 embed · 🖼️ imagen · 🎙️ audio (los de chat no llevan tag).
- **Esconde modelos deprecados/muertos**: `probe-proveedores.py` sondea la API real de
  **cada proveedor** (no solo NVIDIA; el catálogo dice `active` hasta en los que ya no
  existen) y graba `probe-<proveedor>.json`. Esos modelos salen del listado, no se
  etiquetan, y en el picker `/models` quedan marcados `💀 Nombre` (la calavera = no funciona).
- **Watcher automático**: si cambiás `auth.json`, `opencode.json` o `models-rank.json`,
  se regeneran las etiquetas solas (cron de Linux/WSL cada 5 min).
- **`/modelos`**: un comando del TUI para listar modelos por calidad, precio o contexto.
- **Favoritos ordenados**: calidad ↓ y dentro de cada nivel precio ↓.
- Fuente de verdad: `opencode models --verbose` (usa los costos del propio proveedor).

Antes:

```
DeepSeek V4 Flash
Gemini 2.5 Flash
Nemotron 3.5 Lightning (free)
```

Después:

```
⭐🥇🪙 DeepSeek V4 Flash
🥉❷ Gemini 2.5 Flash
🥉🌱 Nemotron 3.5 Lightning (free)
```

¿Cómo se decide cada etiqueta? Está explicado a fondo en
[`METODOLOGIA.md`](METODOLOGIA.md): el baremo de calidad es un ranking curado (no
un benchmark), el costo sale del catálogo oficial de OpenCode, y ambos son editables.

## Requisitos

- **Linux/macOS/WSL:** OpenCode instalado + `python3`.
- **Windows:** OpenCode (terminal o app de escritorio). Python es opcional: si no está,
  el instalador lo instala solo con winget (descarta el alias falso de la Microsoft Store).
- Red (para el catálogo de costos la primera vez).

> **WSL con opencode de Windows:** si en WSL el instalador detecta que el `opencode`
> visible es el de Windows (ruta `/mnt/c/...npm/...`), en modo `aplica` descarga e
> instala automáticamente el opencode **nativo de Linux** en `~/.opencode/bin`
> (sin tocar el de Windows) y etiqueta la config de Linux con el catálogo completo.

## Instalación

> ⚠️ **Elegí el comando de TU sistema.** Hay dos instaladores distintos y cada uno
> funciona **solo** en su sistema:
>
> | Tu sistema | Instalador | Comando |
> |---|---|---|
> | **Linux / macOS / WSL** | `instalar.sh` | `curl ... | bash -s aplica -y` (ver abajo) |
> | **Windows** (PowerShell/CMD) | `instalar.ps1` | el comando `irm ...` de la sección Windows |
>
> El comando `curl | bash` es bash de Linux: en Windows **no existe `bash`**, así que
> ese se lanza ahí **no funciona** (aunque PowerShell tenga un comando `curl`, es un
> alias distinto). Y el `irm` de Windows es solo para Powershell: no lo corras en
> Linux. Ambos instalan **el mismo sistema de etiquetas**, solo que cada uno sabe
> copiar los archivos al lugar correcto de su sistema.

### Linux / macOS / WSL

```bash
curl -fsSL https://raw.githubusercontent.com/kevinyarialmiron/etiquetar-modelos-opencode/main/instalar.sh | bash -s aplica -y
```

`-y` aplica los nombres **y** reordena los Favoritos sin preguntar.

### Windows (PowerShell)

Desde **PowerShell (5.1+) o Windows Terminal**:

```powershell
# descarga el instalador y lo ejecuta
irm https://cdn.jsdelivr.net/gh/kevinyarialmiron/etiquetar-modelos-opencode@main/instalar.ps1 -OutFile "$env:TEMP\instalar-opencode.ps1"
& "$env:TEMP\instalar-opencode.ps1" -aplica -yes
```

Detecta opencode (binario nativo, shim npm o app de escritorio) y Python, copia los
archivos a `%USERPROFILE%\.config\opencode` y aplica. En Windows la config global es
la misma para **terminal y app de escritorio**, así que las etiquetas se ven en ambos.

> **¿Y si la PC no tiene Python?** El instalador lo detecta solo: descarta el alias
> fantasma de la Microsoft Store (el que tira "no se encontró Python...") y, si hace
> falta, instala Python con winget (o te pediría confirmarlo). Cerrá y reabrí la
> terminal después de instalar Python.

### Ruta transparente (clonar y correr)

```bash
gh repo clone kevinyarialmiron/etiquetar-modelos-opencode
cd etiquetar-modelos-opencode
./instalar.sh       # preview (no toca nada)
./instalar.sh aplica -y    # aplica
```

### Modos de `instalar.sh`

| Comando | Qué hace |
|---|---|
| `./instalar.sh` | Copia los archivos y muestra preview del dataset |
| `./instalar.sh aplica` | Aplica los nombres a `opencode.json` (pregunta por Favoritos) |
| `./instalar.sh aplica -y` | Aplica y reordena Favoritos sin preguntar |
| `./instalar.sh aplica -n` | Aplica sin reordenar Favoritos |
| `./instalar.sh --dry-run` | Muestra qué haría sin escribir nada |

### Modos de `instalar.ps1`

| Comando | Qué hace |
|---|---|
| `.\instalar.ps1` | Copia los archivos y muestra preview del dataset |
| `.\instalar.ps1 -aplica` | Aplica los nombres (pregunta por Favoritos) |
| `.\instalar.ps1 -aplica -yes` | Aplica y reordena Favoritos sin preguntar |
| `.\instalar.ps1 -aplica -noFavoritos` | Aplica solo los nombres |
| `.\instalar.ps1 -dryRun` | Muestra qué haría sin escribir nada |

Siempre crea un backup de `opencode.json` (`.bak-etiquetas-<fecha>`) antes de aplicar.

## Personalizar la calidad

El archivo `data/models-rank.json` (que el instalador copia a `~/.config/opencode/data/`)
define qué nivel tiene cada modelo. Tiene tres secciones:

- `override`: asignación directa por ID (`"openrouter/deepseek/deepseek-v4-pro": 1`).
- `niveles`: patrones regex por nivel (`"gemini-3\\.(6|7|8)-flash"` → nivel 2).
- `costos`: precio curado de salida ($/1M tokens) para proveedores cuyo catálogo no
  publica precio (ej. `ollama-cloud`, que trae `$0` aunque es pago). Opcional
  `"peak": true` para marcar cobro ×2 en hora pico → muestra `(🕒🔥x2)`.

Si querés que un modelo suba/baje de nivel, editá ese JSON y volvé a correr
`instalar.sh aplica` (o en Windows `instalar.ps1 -aplica -yes`). Las reglas del
ranking tienen prioridad sobre las etiquetas ya aplicadas, así el cambio se refleja.

También podés **ocultar** modelos a mano agregando su ID (o un regex) a la sección
`ocultar` de `models-rank.json` (ej. `"ocultar": ["openrouter/foo/bar-model"]`).
Los modelos detectados como muertos por el sondeo se suman a esa lista automáticamente.

### Sondeo de modelos deprecados/muertos (todos los proveedores)

Muchos catálogos (sobre todo NVIDIA) listan modelos con `status: active` aunque ya
fueron retirados (dan `410 Gone` / `404` al llamarlos). Para esconderlos:

```bash
python3 ~/.config/opencode/bin/probe-proveedores.py                 # todos los proveedores (chat)
python3 ~/.config/opencode/bin/probe-proveedores.py --prov openrouter   # un solo proveedor
```

Lee la key de cada proveedor en `~/.local/share/opencode/auth.json` (no la imprime),
sondea cada modelo contra su endpoint real (usa `api.url`/`api.npm` que publica
`opencode models --verbose`) y graba un `data/probe-<proveedor>.json` por proveedor.

Reglas conservadoras (nunca marca un muerto de más):
- `200` → vivo · `404/410` → muerto · `401/402/403/429` (auth/cuota/sin saldo) →
  **no verificado** (se conserva el estado previo) · `timeout`/`5xx` → transitorio
  (dudoso, no se esconde).

Dos proveedores **no se sondean de forma confiable** desde fuera (su endpoint exige
el contexto/sesión del propio opencode, o la URL del gateway es opaca): `vercel` y
`opencode` (Zen). Se saltean para no producir muertes falsas. Si querés sondearlos,
hacelo desde dentro de opencode (correr un request por cada modelo y ver el error).

Después de sondear, corré `gen-modelos.py --apply` para reflejar los 💀.

### Watcher automático (Linux/macOS/WSL)

`instalar.sh` programa un cron cada 5 min que reejecuta `gen-modelos.py --apply`
solo si cambió `auth.json`, `opencode.json`, `models-rank.json`, `nvidia-muertos.json`
o el propio `gen-modelos.py`. Los cambios en el picker se ven al recargar opencode.

```bash
crontab -l   # ver la línea */5 * * * * ~/.config/opencode/bin/watch-etiquetas.sh
# forzar una regeneración inmediata:
~/.config/opencode/bin/watch-etiquetas.sh --force
```

## Estructura

```
etiquetar-modelos-opencode/
├── instalar.sh               # instalador bash (autónomo, descarga files/ si es por pipe)
├── instalar.ps1              # instalador PowerShell (Windows, con retry + fallback CDN)
├── METODOLOGIA.md            # cómo se decide cada etiqueta (baremo, costo, fiabilidad)
├── PROMPT.md                 # para instalación guiada por IA en otra instancia
├── LICENSE                   # MIT
└── files/
    ├── gen-modelos.py        # genera las etiquetas (--apply para escribir opencode.json)
    ├── models-rank.json      # reglas de calidad + ocultar (editable)
    ├── modelos.sh            # backend del comando /modelos
    ├── ordenar-favoritos.sh  # wrapper del reorder de Favoritos
    ├── ordenar-favoritos.py  # reorder portable (Linux/macOS/Windows), solo lista favorite
    ├── probe-nvidia.py       # sondeo específico de NVIDIA (legacy: sigue funcionando, chat/--todo/--dudosos)
    ├── probe-proveedores.py  # sondeo generalizado (todos los proveedores, chat) -> data/probe-<prov>.json
    ├── nvidia-muertos.json   # baseline legacy de NVIDIA que ya no responden (fallback si no hay probe-nvidia.json)
    ├── watch-etiquetas.sh    # watcher por cron (regenera si cambió algo relevante)
    └── commands-modelos.md   # definición del slash-command /modelos
```

## FAQ

**¿Cómo se valora la calidad? ¿Sale de un benchmark?**
No. Es un ranking curado a mano (en `models-rank.json`), con `override` por ID y
patrones regex por familia, calibrado con uso real. No hay una "puntuación" numérica
ni un baremo automático (ver [`METODOLOGIA.md`](METODOLOGIA.md)).

**¿Qué ratio de fiabilidad tiene?**
No existe tal número. La medallita es una opinión informada y editable: son **tus**
modelos, cambiá el JSON y regenerá. Calidad y costo son dos ejes independientes que
no se mezclan en una sola fórmula.

**¿Funciona en Windows? ¿Y en la app de escritorio?**
Sí. `instalar.ps1` instala todo en `%USERPROFILE%\.config\opencode\opencode.json`,
config global compartida por la **terminal y la app de escritorio** de OpenCode, así
que las etiquetas se ven en ambas. También funciona reordenar Favoritos en Windows.

**¿Puedo usar el comando `curl | bash` en Windows para instalar?**
No. Ese comando es del instalador de Linux (`instalar.sh`): necesita `bash`, que en
Windows solo existe si tenés WSL. En Windows nativo (PowerShell/CMD) usá el de la
sección **Instalación → Windows**, que descarga `instalar.ps1` con `irm`. Son dos
instaladores distintos que aplican el mismo sistema de etiquetas en cada sistema.

**¿Aplica para todos los proveedores?**
Sí, exactamente los que tu instancia tiene configurados/autenticados (openrouter,
opencode, google, deepseek, ollama, etc.). Si un proveedor no está activo, no aparece.

**¿Toca mis credenciales o config?**
No. Solo agrega/renombra la entrada `name` de cada modelo en `provider.*.models.*`
y crea `commands/modelos.md`. Nunca lee ni escribe tokens.

**¿Rompe algo?** No. Hace backup antes de aplicar y es idempotente: si lo volvés a
correr, reemplaza los nombres sin duplicar prefijos.

**¿Por qué algunos modelos no se etiquetan / no aparecen en `/modelos`?**
Porque ya no funcionan: algunos catálogos de OpenCode los listan como `active`, pero
el proveedor los retiró (dan `410 Gone` / `404` al llamarlos). `probe-proveedores.py`
los detecta por sondeo real y los esconde del listado y del etiquetado. En el picker
`/models` quedan con el nombre marcado `💀` delante, para que se vea a simple vista
que están fuera de servicio y no se confundan con los que funcionan. (Los que no
pudieron verificarse por falta de saldo del proveedor quedan intactos, sin `💀`.)

**¿Por qué veo pocos modelos (ej. ~69 en vez de ~500)?** Suele pasar en WSL cuando
el `opencode` del PATH es el de **Windows** (npm en `/mnt/c/...`): el catálogo sale
de esa config, no de la de Linux. El instalador detecta el caso y, en `aplica`,
instala el opencode nativo de Linux y usa ese binario. Si ya aplicaste con el
binario equivocado, corré de nuevo: `./instalar.sh aplica -y`.

**¿Los costos son exactos?** Vienen del catálogo de OpenCode (`--verbose`); son
referenciales y cambian. Regenerá cuando quieras con `gen-modelos.py --apply`
(o `instalar.ps1 -aplica`).

**¿Por qué mis Favoritos no cambian al instalar?**
Reordenar la pestaña Favoritos toca el estado (`~/.local/state/opencode/model.json`)
que OpenCode mantiene en memoria: cerrá el TUI, corré la instalación o
`ordenar-favoritos.sh`, y volvé a abrirlo. Recientes y selección actual no se tocan.

## Licencia

[MIT](LICENSE). Podés verlo, descargarlo, usarlo y redistribuirlo.