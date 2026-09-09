# Etiquetar Modelos de OpenCode

Etiqueta automáticamente **todos los modelos** del selector `/models` de [OpenCode](https://opencode.ai)
con su **calidad** y su **costo por 1M de tokens**, y ordena la pestaña **Favoritos**
por calidad y precio. Con dos comandos tenés el picker legible de una vez.

## Qué hace

- **496 modelos** (openrouter, opencode, opencode-go, google, deepseek, ollama) etiquetados al instante.
- **Calidad**: ⭐🥇 nivel 1 (más confiable) · 🥈 nivel 2 · 🥉 nivel 3 · 🏅 nivel 4 · *sin medalla = evitar*.
- **Costo** (salida por 1M tokens): 🌱 gratis · 🪙 centavos · ❶ $1-2 · ❷ $2-3 · … · ❺❗ $5-6 · ❿❗ ≥$10.
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

## Requisitos

- OpenCode instalado (Linux, macOS o WSL). Si no lo tenés: `curl -fsSL https://opencode.ai/install | bash`
- `python3`
- Red (para el catálogo de costos la primera vez).

> **WSL con opencode de Windows:** si en WSL el instalador detecta que el `opencode`
> visible es el de Windows (ruta `/mnt/c/...npm/...`), en modo `aplica` descarga e
> instala automáticamente el opencode **nativo de Linux** en `~/.opencode/bin`
> (sin tocar el de Windows) y etiqueta la config de Linux con el catálogo completo.
> No tenés que desinstalar nada en Windows.

## Instalación

### Ruta rápida (una línea)

```bash
curl -fsSL https://raw.githubusercontent.com/kevinyarialmiron/etiquetar-modelos-opencode/main/instalar.sh | bash -s aplica -y
```

`-y` aplica los nombres **y** reordena los Favoritos sin preguntar.

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

Siempre crea un backup de `opencode.json` (`.bak-etiquetas-<fecha>`) antes de aplicar.

## Personalizar la calidad

El archivo `data/models-rank.json` (que el instalador copia a `~/.config/opencode/data/`)
define qué nivel tiene cada modelo. Tiene dos secciones:

- `override`: asignación directa por ID (`"openrouter/deepseek/deepseek-v4-pro": 1`).
- `niveles`: patrones regex por nivel (`"gemini-3\\.(6|7|8)-flash"` → nivel 2).

Si querés que un modelo suba/baje de nivel, editá ese JSON y volvé a correr
`instalar.sh aplica`.

## Estructura

```
etiquetar-modelos-opencode/
├── instalar.sh               # instalador (autónomo, descarga files/ si es por pipe)
├── PROMPT.md                 # para instalación guiada por IA en otra instancia
└── files/
    ├── gen-modelos.py        # genera las etiquetas (--apply para escribir opencode.json)
    ├── models-rank.json      # reglas de calidad (editable)
    ├── modelos.sh            # backend del comando /modelos
    ├── ordenar-favoritos.sh  # reordena la pestaña Favoritos
    └── commands-modelos.md   # definición del slash-command /modelos
```

## FAQ

**¿Toca mis credenciales o config?**
No. Solo agrega/renombra la entrada `name` de cada modelo en `provider.*.models.*`
y crea `commands/modelos.md`. Nunca lee ni escribe tokens.

**¿Rompe algo?** No. Hace backup antes de aplicar y es idempotente: si lo volvés a
correr, reemplaza los nombres sin duplicar prefijos.

**¿Y si no tengo todos los proveedores?** Etiqueta solo los que tu opencode ve en
`opencode models` (los que están autenticados/configurados).

**¿Por qué veo pocos modelos (ej. ~69 en vez de 400+)?** Suele pasar en WSL cuando
el `opencode` del PATH es el de **Windows** (npm en `/mnt/c/...`): el catálogo sale
de esa config, no de la de Linux. El instalador detecta el caso y, en `aplica`,
instala el opencode nativo de Linux y usa ese binario — con lo que el catálogo pasa
a ser el completo de tu Linux. Si ya aplicaste con el binario equivocado, corré de
nuevo: `./instalar.sh aplica -y`.

**¿Los costos son exactos?** Vienen del catálogo de OpenCode (`--verbose`); son
referenciales y cambian. Regenerá cuando quieras con `gen-modelos.py --apply`.

## Licencia

Sin licencia: el código puede verse y descargarse, pero no redistribuirse.