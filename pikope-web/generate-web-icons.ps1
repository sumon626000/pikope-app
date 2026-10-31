# Copy app icon into web/ for PWA + favicon (no resize; browsers scale).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here
$src = Join-Path $root 'assets\icon\app_icon.png'
if (-not (Test-Path $src)) {
    Write-Warning "Missing $src - skip icon copy."
    exit 0
}
$iconDir = Join-Path $here 'web\icons'
New-Item -ItemType Directory -Force -Path $iconDir | Out-Null
Copy-Item -Force $src (Join-Path $here 'web\favicon.png')
foreach ($name in @('Icon-192.png', 'Icon-512.png', 'Icon-maskable-192.png', 'Icon-maskable-512.png')) {
    Copy-Item -Force $src (Join-Path $iconDir $name)
}
Write-Host "Web icons updated from assets/icon/app_icon.png"
