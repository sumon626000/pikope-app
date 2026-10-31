# One-time (or after clone): link shared assets from the Android app tree.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here
$assets = Join-Path $here 'assets'
$target = Join-Path $root 'assets'

if (-not (Test-Path $target)) {
    Write-Error "Missing $target - run from duelx repo with assets/"
}

if (Test-Path $assets) {
    Write-Host "assets/ already present (junction or folder)."
} else {
    cmd /c "mklink /J `"$assets`" `"$target`""
    Write-Host "Created junction: pikope-web/assets -> ../assets"
}

$flutter = 'C:\Users\sumon\Downloads\flutter_windows_3.44.5-stable\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

& (Join-Path $here 'generate-web-icons.ps1')

Push-Location $here
& $flutter pub get
Pop-Location

Write-Host "Done. Run: .\run-local.ps1"
