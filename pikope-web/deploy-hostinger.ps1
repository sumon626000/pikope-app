# Build release web app and pack for Hostinger upload.
param(
    [string]$BaseHref = '/',
    [string]$ZipOut = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here
& (Join-Path $here 'generate-web-icons.ps1')

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
& $flutter build web --release --base-href $BaseHref @define
$out = Join-Path $here 'build\web'
if ($ZipOut -eq '') {
    $ZipOut = Join-Path $here ('dist\pikope-web-' + (Get-Date -Format 'yyyyMMdd-HHmm') + '.zip')
}
$dist = Split-Path -Parent $ZipOut
New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $ZipOut) { Remove-Item -Force $ZipOut }
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $ZipOut
Pop-Location

Write-Host ""
Write-Host "Built: $out"
Write-Host "Zip:   $ZipOut"
Write-Host "Upload zip contents to Hostinger public_html (or play subdomain document root)."
Write-Host "See DEPLOY.txt"
