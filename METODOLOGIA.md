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

### Criterio por familia (cómo se decide cada nivel)

El criterio es consistente entre proveedores: **un mismo modelo vale lo mismo
abriéndolo desde openrouter, opencode o opencode-go**. Las reglas buscan por
**familia** (regex) y el `override` solo corrige casos puntuales.

- **1 ⭐🥇 (frontera):** los mejores de cada laboratorio de IA — últimas
  generaciones *grandes* (`gpt-6`, `gemini-3.x-pro`, `claude-*-5`,
  `glm-5.3`, `kimi-k3`, `qwen3.7/3.8-max`, `gpt-5.2+`, `astra`, `deepseek-v4-pro`).
- **2 🥈 (muy bueno):** generaciones recientes *normales o flash* — `gpt-5`,
  `claude-fable-5`, `glm-5.x`, `gemini-3.x-flash/lite/omni`, `qwen3.6+/3.7/3.8`,
  `hy4`, `minimax-m3/m2.7`, `seed-2.1`, `nova-premier`, `kimi-k2.6/7`, `grok-build`.
- **3 🥉 (sólido/decente):** gamas medias o especialistas — `qwen3.5/coder`,
  `gemma-4`, `gpt-oss`, `muse`, `ling-3`, `seed`, `nemotron-3-super/nano`,
  `mistral-small-3.x`, `laguna`, `mercury-2.5`, `glm-4.7+`, `grok-4`.
- **4 🏅 (funciona pero antiguo):** generaciones pasadas — `gpt-3.5/4`,
  `o1/o3/o4`, `claude-3`, `gemini-2`, `llama-3`, `qwen2.5/3-8b`, `mistral
  grande/medium vieja`, `ministral`, `gemma-2/3`, `mixtral`, `deepseek-r1/chat`,
  `minimax-m1/m2`, `phi-4`.
- **sin medalla = evitar:** finetunes de rol/RP, micro-modelos, espejos `~`,
  y modelos de imagen/audio/video/embedding (no son chat; no se califican).

En la duda, un modelo sin medalla es mejor que una medalla dudosa: la ausencia
te avisa que no es recomendado por defecto, no que esté roto.

### Razonamiento y costo: sort por separado

Calidad y costo son **dos ejes independientes** que se muestran juntos pero no se
combinan en una sola fórmula. En la pestaña Favoritos el orden es:

1. **Calidad** primero (mejores arriba).
2. Dentro del mismo nivel, **costo descendente** (más caro arriba, gratis al final).

Así podés elegir "quiero lo mejor" (arriba) o "lo mejor que me alcance"
(corriendo el ojo hacia abajo).

## Costo: dato oficial del proveedor (con tabla curada donde falta)

El costo sale del **catálogo oficial de opencode** (`opencode models --verbose`),
que publica el precio de **salida por 1M de tokens** de cada proveedor. No se
inventa ni se cachea en el repo; se lee en vivo al generar. Detalles:

- **🌱 gratis** (`$0`) · **🪙 centavos** (`< $1`) · **❶–❹** ($1–5) · **❺❗–❿❗** (>$5, con ❗).
- Los modelos de **ollama local** (self-hosted) siempre cuentan como gratis.
- **Proveedores sin precio en el catálogo**: algunos (ej. **ollama-cloud**, que es
  pago por uso) traen `cost: 0` en el catálogo, lo que daría un 🌱 falso. Para esos,
  `models-rank.json` tiene una sección **`costos`** curada a mano (precio de salida
  por 1M de tokens, fuente: la página de precios del proveedor). Manda sobre el
  catálogo. Ejemplo: `"ollama-cloud/kimi-k3": {"out": 15.00}`.
- **Precio pico**: si un proveedor cobra distinto según la hora (ollama-cloud cobra
  **×2** de 12:00 a 18:00 UTC, lunes a viernes), la entrada lleva `"peak": true` y el
  nombre muestra el aviso **`(🕒🔥x2)`** al final. El precio mostrado es siempre el
  estándar (fuera de pico); el aviso recuerda que en pico se duplica.
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

## Modelos muertos/deprecados: se ocultan y se marcan con 💀

Algunos catálogos (sobre todo NVIDIA) listan modelos con `status: active` **aún
después de retirarlos**: al llamarlos dan `410 Gone` ("end of life") o `404`. Una
etiqueta bonita ahí sería una trampa. Por eso:

- `probe-proveedores.py` sondea la API real de **cada proveedor** con un request
  mínimo por modelo (respeta la key de cada provider en
  `~/.local/share/opencode/auth.json`, sin imprimirla) y guarda el resultado en
  `~/.config/opencode/data/probe-<proveedor>.json`. Usa el `api.url`/`api.npm` que
  publica `opencode models --verbose`, así que no requiere hardcodear endpoints por
  proveedor (salvo los que no exponen URL, con una tabla corta en el propio script).
- `gen-modelos.py` **oculta** todo lo que está en esos archivos: no aparece en
  `data/modelos.json` (ni en `/modelos` ni en Favoritos) y no se etiqueta. Además,
  en el picker `/models` **todo** modelo muerto se marca `💀 <nombre>` (se crea la
  entrada aunque no existiera antes), para que se vea a simple vista que está
  fuera de servicio y nunca se confunda con uno útil.
- Regla de conservadurismo (nunca falso-muerto):
  - `200` → vivo; `404/410` (o un `4xx` con pista inequívoca de "modelo retirado")
    → muerto definitivo.
  - `401/402/403/429` (auth, falta de saldo, cuota) → **no verificado**: se conserva
    el estado previo y **nunca** se esconde un modelo por eso.
  - `timeout`/`5xx` → transitorio: nunca esconde a un modelo antes vivo; si no hay
    historial queda como "dudoso" (también sin esconder). Importante: **solo un 4xx
    definitivo esconde**; un "timeout" jamás marca `💀`.
  - Los "dudosos" de NVIDIA se pueden re-sondear con `python3 bin/probe-nvidia.py
    --dudosos` (más paciencia; un 200 los pasa a vivos).
- **No todos los proveedores se pueden sondear desde fuera**: `vercel` y `opencode`
  (Zen) exigen el contexto/sesión del propio opencode (o una URL de gateway opaca),
  así que se saltean para no producir muertes falsas. Esos modelos se dejan como
  están (con su etiqueta de catálogo). Si querés "verificar" uno de esos en
  particular, es más fiable correrle un request *desde* opencode y leer el error.
- `models-rank.json` admite una sección `ocultar` con IDs exactos o regex para
  esconder modelos a mano (cualquier proveedor); esos también se marcan `💀`.

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