# Metodología — cómo se etiqueta cada modelo

Esto responde las preguntas más frecuentes: **¿bajo qué baremo se clasifica?**,
**¿de dónde sale la puntuación?** y **¿qué fiabilidad tiene?**

## Calidad: un ranking curado, no un benchmark

El nivel de calidad (⭐🥇🥈🥉🏅) **no** sale de un benchmark automático. Es un
ranking **curado a mano**, calibrado con el uso real en producción (agentes y
sessions que corren día a día con estos modelos), y vive en un archivo editable:

- `~/.config/opencode/data/models-rank.json` (fuente: `files/models-rank.json`)

Tiene dos secciones:

| Sección | Qué es | Ejemplo |
|---|---|---|
| `override` | Asignación directa de nivel por ID exacto | `"openrouter/deepseek/deepseek-v4-pro": 1` |
| `niveles` | Patrones regex por familia de modelo | `"gemini-3\\.(6|7|8)-pro"` → nivel 1 |

El significado de cada nivel:

- **1 ⭐🥇** — modelos con los que el proyecto tiene mejor experiencia real
  (menos errores, mejor razonamiento en la práctica).
- **2 🥈** — muy buenos, apenas por debajo.
- **3 🥉** — sólidos pero con limitaciones conocidas.
- **4 🏅** — funcionan pero no son la mejor opción.
- **sin medalla** — no están en el ranking: *evitar por defecto*.

> ⚠️ **Fiabilidad:** es una opinión informada, no un número. La regla de oro:
> son **tus** modelos; editá `models-rank.json` y volvé a correr
> `./instalar.sh aplica` (o `gen-modelos.py --apply`) para que el ranking
> refleje tu experiencia.

### Razonamiento y costo: sort por separado

Calidad y costo son **dos ejes independientes** que se muestran juntos pero no se
combinan en una sola fórmula. En la pestaña Favoritos el orden es:

1. **Calidad** primero (mejores arriba).
2. Dentro del mismo nivel, **costo descendente** (más caro arriba, gratis al final).

Así podés elegir "quiero lo mejor" (arriba) o "lo mejor que me alcance"
(corriendo el ojo hacia abajo).

## Costo: dato oficial del proveedor

El costo sale del **catálogo oficial de opencode** (`opencode models --verbose`),
que publica el precio de **salida por 1M de tokens** de cada proveedor. No se
inventa ni se cachea en el repo; se lee en vivo al generar. Detalles:

- **🌱 gratis** (`$0`) · **🪙 centavos** (`< $1`) · **❶–❹** ($1–5) · **❺❗–❿❗** (>$5, con ❗).
- Los modelos de **ollama** (locales) siempre cuentan como gratis.
- Los precios cambian con los proveedores: regenerá cuando quieras con
  `python3 ~/.config/opencode/bin/gen-modelos.py --apply`.

## Proveedores: se etiqueta lo que tu opencode "ve"

`opencode models --verbose` lista los modelos de los proveedores que tu instancia
tiene **configurados/autenticados** (openrouter, opencode, google, deepseek,
ollama, etc.). La herramienta etiqueta **todo eso**, en cualquier combinación. Si
un proveedor no está activo, sus modelos no aparecen — y no se etiquetan.

## Windows (terminal y desktop)

La config global de opencode vive en la misma ruta relativa en todas las
plataformas:

- Linux/macOS: `~/.config/opencode/opencode.json`
- Windows: `%USERPROFILE%\.config\opencode\opencode.json`

El **TUI de terminal** y la **app de escritorio** comparten esa config, así que
las etiquetas aplicadas se ven en ambos. En Windows se instala con
`instalar.ps1` (PowerShell); en Linux/macOS/WSL con `instalar.sh`.

## El orden de Favoritos y el TUI

opencode mantiene el estado (favoritos/recientes) en
`~/.local/state/opencode/model.json`. La herramienta solo reordena la lista
`favorite`, **sin tocar** recientes ni la selección actual. Dos reglas:

1. Corré el reorden **con el TUI cerrado** (si está abierto, la copia en memoria
   puede pisar el cambio al salir) — o reiniciá el TUI después.
2. Si corriste la instalación antes de abrir opencode por primera vez, generá
   el `model.json` abriendo el TUI una vez y volvé a correr el reorden.