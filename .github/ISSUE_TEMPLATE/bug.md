---
name: Reporte de bug
about: Algo funciona mal (instalador, etiquetas, sondeo, tests)
title: "[Bug] título corto del problema"
labels: bug
---

<!-- Sin estos datos es muy difícil reproducir el problema. Completá lo que puedas. -->

## Entorno

- **Sistema operativo:** [ej. Windows 11, Ubuntu 24.04, WSL2]
- **Terminal / shell:** [ej. PowerShell 5.1, bash, Windows Terminal]
- **Versión de opencode** (`opencode --version`): [ej. …]
- **Cómo instalaste opencode:** [binario oficial / npm / app de escritorio]
- **Cómo instalaste el sistema de etiquetas:** [`instalar.ps1` / `instalar.sh` / cloné el repo]

## Qué pasó

Descripción clara y concisa del problema.

## Cómo reproducirlo

Pasos (solo los necesarios):

1. Instalé con `…`
2. Corrí `…`
3. Pasó esto: `…`

## Qué esperaba

Qué debería haber pasado si todo estuviera bien.

## Error / salida

Pegá el error **tal cual** (sin resumir). Si es largo, usá un bloque de código
o adjuntalo.

## Más contexto

- ¿Corrió la suite de tests antes? (`./tests/run.sh` → `X pasan, Y fallan`)
- ¿`--apply` es idempotente en tu caso (correrlo dos veces no rompe
  `opencode.json`)?
- ¿El backup `.bak-etiquetas-*` se creó?
- Capturas de pantalla útiles, si hay.

Confirmás que **no** subiste datos de tu máquina (`data/`) en el reporte.