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

## Tipo: chat, embed, imagen, audio

Cada modelo se clasifica por sus `capabilities` del catálogo y eso se muestra como
tag en el nombre (solo los no-chat, para no ensuciar los que se usan de a diario):

- (sin tag) — **chat** (incluye vision/razonamiento de chat).
- 🧩 — **embed** (embeddings, rerank, safety, código de otro dominio).
- 🖼️ — **imagen** (generación).
- 🎙️ — **audio** (TTS/STT/transcripción).

El campo `tipo` se guarda además en `data/modelos.json` y lo muestra `/modelos`.

## Modelos muertos/deprecados: se ocultan, no se marcan como confiables

El catálogo de NVIDIA (`opencode models --verbose`) lista sus modelos con
`status: active` **aún después de retirarlos**: al llamarlos dan `410 Gone`
("end of life") o `404`. Una etiqueta bonita ahí sería una trampa. Por eso:

- `probe-nvidia.py` sondea la API real de NVIDIA con un request mínimo por modelo
  (respeta la key de `~/.local/share/opencode/auth.json`, sin imprimirla) y guarda
  el resultado en `~/.config/opencode/data/nvidia-muertos.json`.
- `gen-modelos.py` **oculta** todo lo que está en ese archivo: no aparece en
  `data/modelos.json` (ni en `/modelos` ni en Favoritos) y no se etiqueta. Si un
  modelo ya estaba etiquetado y muere, se vuelve a nombrar `⛔ <nombre>` para que
  se vea que está fuera de servicio.
- Regla de conservadurismo: un **timeout** (cold start de hasta 120 s en NVIDIA) no
  degrada a un modelo ya confirmado vivo; solo un 4xx/5xx definitivo lo esconde.
- `models-rank.json` admite una sección `ocultar` con IDs exactos o regex para
  esconder modelos a mano (cualquier proveedor).

## Proveedores: se etiqueta lo que tu opencode "ve"

`opencode models --verbose` lista los modelos de los proveedores que tu instancia
tiene **configurados/autenticados** (openrouter, opencode, google, deepseek,
ollama, **nvidia**, etc.). La herramienta etiqueta **todo eso**, en cualquier
combinación. Si un proveedor no está activo, sus modelos no aparecen — y no se
etiquetan. Un proveedor nuevo que agregues a `auth.json`/`opencode.json` se detecta
solo (y el watcher lo vuelve a detectar en ≤5 min).

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