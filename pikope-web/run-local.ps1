# Local web dev (Chrome). Uses parent .env for API_BASE_URL when present.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here
$envFile = Join-Path $root '.env'
$define = @()
if (Test-Path $envFile) {
    $define = @('--dart-define-from-file', $envFile)
} else {
    Write-Warning "No ../.env - copy .env.example to duelx/.env for API_BASE_URL."
}

$flutter = 'C:\Users\sumon\Downloads\flutter_windows_3.44.5-stable\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

Push-Location $here
if (-not (Test-Path 'assets')) {
    & (Join-Path $here 'setup-local.ps1')
}
& $flutter run -d chrome @define
Pop-Location
