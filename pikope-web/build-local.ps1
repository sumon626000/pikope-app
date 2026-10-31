# Release web build -> pikope-web/build/web (upload to Hostinger in Phase 4).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here
$envFile = Join-Path $root '.env'
$define = @()
if (Test-Path $envFile) {
    $define = @('--dart-define-from-file', $envFile)
}

$flutter = 'C:\Users\sumon\Downloads\flutter_windows_3.44.5-stable\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

Push-Location $here
if (-not (Test-Path 'assets')) {
    & (Join-Path $here 'setup-local.ps1')
}
& (Join-Path $here 'generate-web-icons.ps1')
& $flutter build web --release @define
Pop-Location
Write-Host "Output: pikope-web\build\web"
