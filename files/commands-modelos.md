---
description: Lista modelos con etiquetas de calidad y costo, ordenados (calidad, precio o contexto). Ej: /modelos, /modelos barato, /modelos openrouter barato
agent: build
---

Ejecutá el script `~/.config/opencode/bin/modelos.sh` con los argumentos `$ARGUMENTS` y mostrá su salida EXACTA tal cual, como texto, sin resumir ni agregar comentarios ni markdown de código.

Si `$ARGUMENTS` está vacío, ejecutá `~/.config/opencode/bin/modelos.sh`.

Reglas:
- No interpretar, no modificar, no filtrar la salida del script.
- Si el script falla, mostrá su stderr.