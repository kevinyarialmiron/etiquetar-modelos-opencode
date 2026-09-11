# Contribuir

¡Gracias! Este proyecto es chico y está pensado para que aportar sea fácil.
Antes de abrir un issue o un PR, leé esta guía: te ahorra tiempo y a
nosotros también.

## Cómo está organizado

- `files/gen-modelos.py` — el corazón: genera el dataset y, con `--apply`,
  escribe los nombres en `opencode.json`. Idempotente (volver a correrlo no
  duplica prefijos).
- `files/models-rank.json` — las reglas editables (niveles, `override`,
  `ocultar`, `costos`). Casi todo cambio de calidad/costo es tocar este JSON.
- `files/probe-*.py` — sondeo de modelos muertos contra la API real de cada
  proveedor (escribe `data/probe-<prov>.json`).
- `instalar.sh` / `instalar.ps1` — instaladores. Copian `files/` a
  `~/.config/opencode/` y aplican.
- `tests/` — suite end-to-end (ver abajo).

## Requisitos para desarrollar

- `git`, `bash` y `python3`.
- Para correr la **suite de tests**: solo `bash` + `python3`. No necesitás
  opencode ni tocar tu config: cada test corre en un `HOME` falso con un
  *shim* que responde `models --verbose` con un catálogo fijo
  (`tests/fixtures/verbose.txt`).
- Para probar el instalador de verdad: `opencode` y, en Windows,
  `instalar.ps1` con PowerShell.

## Correr la suite

```bash
./tests/run.sh            # la suite completa (10 tests)
./tests/run.sh t_gen      # un test puntual
```

Debe terminar en `===== 10 pasan, 0 fallan =====` (exit 0). Es el pre-commit:
si rompés la suite, no mandes el PR. GitHub también la corre automáticamente
por cada push/PR (el badge del README).

## Reglas de oro

1. **No rompas la idempotencia.** Correr `--apply` dos veces seguidas debe dar
   exactamente el mismo `opencode.json`. El test `t_idempotencia` lo verifica.
2. **Toda regla nueva lleva su test.** Si agregás lógica nueva a un `.py`,
   sumá (o adaptá) una aserción en la suite. Así el CI vigila tu cambio para
   siempre.
3. **Python 3 estándar.** Nada de dependencias nuevas salvo `requests`
   (usada por el sondeo y ya instalada por ambos instaladores).
4. **Bash defensivo.** En `instalar.sh` y los `.sh` de `files/` se usa
   `set -euo pipefail`. Mantenelo.
5. **No subas datos de tu máquina.** `data/`, `*.bak*` y `tests/tmp/` están
   en `.gitignore` por algo: son el resultado del sondeo de TU opencode.
6. **Documentá el porqué.** El README explica cómo funciona y cada cosa para
   qué sirve; si cambiás comportamiento, actualizalo. La gente lee el README,
   no el código.

## Flujo para un PR

1. Fork del repo y cloná tu copia.
2. Branch descriptiva: `fix/salida-bash`, `docs/instalacion-windows`, etc.
3. Hacé tu cambio + su test + actualizá README/METODOLOGIA si corresponde.
4. `./tests/run.sh` en verde, luego commit con mensaje que explique el *porqué*.
5. PR contra `main`. El CI corre la suite solo; si queda roja, arreglalo antes
   de pedir review.

## Reportar un bug

Usá la plantilla de issues (botón *New issue* → *Bug*): sistema operativo,
versión de opencode, qué corriste y el error tal cual. Sin esos datos es
muy difícil reproducir algo.