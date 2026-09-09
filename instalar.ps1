<#
.SYNOPSIS
  Instala las etiquetas de calidad+costo de modelos en opencode (Windows terminal / desktop).
.DESCRIPTION
  Detecta opencode y Python, copia los archivos a %USERPROFILE%\.config\opencode
  y aplica los nombres a opencode.json. Con -yes reordena la pestana Favoritos.
  Retry automatico y fallback a CDN (jsdelivr) si raw.githubusercontent falla (429).
.PARAMETER aplica    Aplica los nombres a opencode.json.
.PARAMETER yes       Aplica y reordena Favoritos sin preguntar (-aplica -yes).
.PARAMETER noFavoritos  Aplica sin reordenar Favoritos.
.PARAMETER dryRun    Muestra que haria sin escribir nada.
.PARAMETER noWatcher Plural/singular: en Windows no hay cron. Definir $env:INSTALAR_NO_CRON=1
                     omite la programacion del watcher (se corre manualmente con watch-etiquetas.sh).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File instalar.ps1 -aplica -yes
.NOTES
  Instalacion remota (desde CMD):
    powershell -ExecutionPolicy Bypass -Command "irm https://cdn.jsdelivr.net/gh/kevinyarialmiron/etiquetar-modelos-opencode@main/instalar.ps1 -OutFile $env:TEMP\instalar-opencode.ps1; & $env:TEMP\instalar-opencode.ps1 -aplica -yes"
#>
[CmdletBinding()]
param(
  [switch]$aplica,
  [switch]$yes,
  [switch]$noFavoritos,
  [switch]$dryRun
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Run-Py {
  param([string]$script, [string[]]$args)
  $env:OPENCODE_BIN = $Oc
  $env:PYTHONIOENCODING = "utf-8"
  & $Py $script @args
  if ($LASTEXITCODE -ne 0) { Err "fallo: $script (exit $LASTEXITCODE)" }
}

function Get-Installable {
  param([string]$rel)
  $out = Join-Path $SRC (Split-Path $rel -Leaf)
  foreach ($base in @($RawBase, $CdnBase)) {
    for ($i = 1; $i -le 3; $i++) {
      try {
        Invoke-WebRequest -UseBasicParsing -Uri "$base/$rel" -OutFile $out -TimeoutSec 60 -ErrorAction Stop
        if ((Get-Item $out).Length -gt 0) { return $true }
      } catch {
        Start-Sleep -Milliseconds 800
      }
    }
  }
  return $false
}

$RepoOwner = "kevinyarialmiron"
$RepoName  = "etiquetar-modelos-opencode"
$Branch    = "main"
$RawBase   = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"
$CdnBase   = "https://cdn.jsdelivr.net/gh/$RepoOwner/$RepoName@$Branch"

$homeDir    = $env:USERPROFILE
$CFG     = Join-Path $homeDir ".config\opencode"
$BIN     = Join-Path $CFG "bin"
$DATA    = Join-Path $CFG "data"
$CMDS    = Join-Path $CFG "commands"
$CONFIG  = Join-Path $CFG "opencode.json"
$STATE   = Join-Path $homeDir ".local\state\opencode\model.json"

function Err([string]$m)  { Write-Host "[instalar] ERROR: $m" -ForegroundColor Red; exit 1 }
function Warn([string]$m) { Write-Host "[instalar] AVISO: $m" -ForegroundColor Yellow }

# python ---------------------------------------------------------------
$Py = $null
foreach ($c in @("python", "py", "python3")) {
  $g = Get-Command $c -ErrorAction SilentlyContinue
  if ($g) { $Py = $g.Source; break }
}
if (-not $Py) { Err "Necesitas Python para generar las etiquetas. Instaldo desde python.org y reintenta." }

# opencode -------------------------------------------------------------
$Oc = $null
$native = Join-Path $homeDir ".opencode\bin\opencode.exe"
if (Test-Path $native) {
  $Oc = $native
} else {
  $g = Get-Command opencode -ErrorAction SilentlyContinue
  if ($g) { $Oc = $g.Source }
}
if (-not $Oc) {
  # shim global típico de npm aun si no está en PATH de esta sesión
  $npmShim = Join-Path $env:APPDATA "npm\opencode.cmd"
  if (Test-Path $npmShim) { $Oc = $npmShim }
}
if (-not $Oc) {
  # app de escritorio de opencode (incluye el binario CLI)
  $desktop = Join-Path $env:LOCALAPPDATA "Programs\@opencode-aidesktop\OpenCode.exe"
  if (Test-Path $desktop) { $Oc = $desktop }
}
if (-not $Oc) {
  Err "opencode no encontrado. Instaldo con: curl -fsSL https://opencode.ai/install | bash  (o desde https://opencode.ai)"
}
Write-Host "[instalar] opencode: $Oc"
if ($Oc -match '\.(cmd|bat)$') {
  Warn "El opencode detectado es un shim de npm (.cmd). Si el catalogo sale chico o falla, instaldo opencode con https://opencode.ai/install (crea opencode.exe)."
}

# descargar archivos (local si hay clone) ------------------------------
$files = @("gen-modelos.py", "models-rank.json", "modelos.sh",
           "ordenar-favoritos.sh", "ordenar-favoritos.py", "commands-modelos.md",
           "probe-nvidia.py", "nvidia-muertos.json", "watch-etiquetas.sh")

$SRC = Join-Path $PSScriptRoot "files"
if (-not (Test-Path $SRC)) {
  Write-Host "[instalar] descargando archivos desde $RawBase/files/"
  $SRC = Join-Path $env:TEMP "opencode-etiquetas-files"
  New-Item -ItemType Directory -Force -Path $SRC | Out-Null
  foreach ($f in $files) {
    if (-not (Get-Installable "files/$f")) { Err "fallo descargar $f desde el repo. Revisa conexion o clona el repo y corre el .ps1 local." }
  }
}

$gm = Join-Path $SRC "gen-modelos.py"
if (-not (Test-Path $gm)) { Err "falta gen-modelos.py en $SRC" }
if (-not ((Get-Content -Raw $gm).StartsWith("#!"))) {
  Err "gen-modelos.py baja corrupto (contenido HTML/error?). Reintenta en unos minutos o clona el repo."
}

# dry-run --------------------------------------------------------------
if ($dryRun) {
  Write-Host "[instalar] DRY-RUN - no se escribio nada."
  foreach ($f in $files) { Write-Host "  -> $(Join-Path $CFG $f)" }
  if ($aplica) { Write-Host "  -> $CONFIG (con backup .bak-etiquetas-<ts>)" }
  exit 0
}

# copias + backup ------------------------------------------------------
New-Item -ItemType Directory -Force -Path $BIN, $DATA, $CMDS | Out-Null
$copyPlan = @{
  "gen-modelos.py"       = Join-Path $BIN  "gen-modelos.py"
  "models-rank.json"     = Join-Path $DATA "models-rank.json"
  "modelos.sh"           = Join-Path $BIN  "modelos.sh"
  "ordenar-favoritos.sh" = Join-Path $BIN  "ordenar-favoritos.sh"
  "ordenar-favoritos.py" = Join-Path $BIN  "ordenar-favoritos.py"
  "commands-modelos.md"  = Join-Path $CMDS "modelos.md"
  "probe-nvidia.py"      = Join-Path $BIN  "probe-nvidia.py"
  "nvidia-muertos.json"  = Join-Path $DATA "nvidia-muertos.json"
  "watch-etiquetas.sh"   = Join-Path $BIN  "watch-etiquetas.sh"
}
foreach ($k in $copyPlan.Keys) {
  Copy-Item (Join-Path $SRC $k) $copyPlan[$k] -Force
  Write-Host "  copiado: $($copyPlan[$k])"
}

if (Test-Path $CONFIG) {
  $ts  = Get-Date -Format "yyyyMMdd-HHmmss"
  $bak = "$CONFIG.bak-etiquetas-$ts"
  Copy-Item $CONFIG $bak -Force
  Write-Host "[instalar] backup: $bak"
}

if (-not $aplica) {
  Write-Host "[instalar] preview del dataset:"
  Run-Py (Join-Path $BIN "gen-modelos.py")
  Write-Host ""
  Write-Host "Ejecuta .\instalar.ps1 -aplica -yes para aplicar los nombres a opencode.json."
  exit 0
}

# aplicar --------------------------------------------------------------
Write-Host "[instalar] aplicando etiquetas a opencode.json..."
Run-Py (Join-Path $BIN "gen-modelos.py") --apply
Write-Host "[instalar] LISTO. Reinicia opencode para ver los cambios en /models."

# favoritos ------------------------------------------------------------
if (-not $noFavoritos) {
  $doOrder = $false
  if ($yes) { $doOrder = $true }
  elseif ($Host.Name -ne "ConsoleHost") { $doOrder = $false }
  else {
    $resp = Read-Host "Reordenar tambien los Favoritos (calidad down, precio down)? [s/N]"
    if ($resp -match '^(s|si|s[iI]|y)$') { $doOrder = $true }
  }
  if ($doOrder) {
    if (Test-Path $STATE) {
      Write-Host "[instalar] reordenando Favoritos..."
      Run-Py (Join-Path $BIN "ordenar-favoritos.py") $STATE (Join-Path $DATA "modelos.json")
    } else {
      Warn "no se reordenaron los Favoritos: no existe $STATE. Abri opencode una vez y reintenta: python $(Join-Path $BIN 'ordenar-favoritos.py')"
    }
  }
}