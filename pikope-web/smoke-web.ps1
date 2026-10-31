# Phase 5: automated smoke before release (local).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here

$flutter = 'C:\Users\sumon\Downloads\flutter_windows_3.44.5-stable\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

Write-Host "=== Parent widget tests (shared lib) ==="
Push-Location $root
& $flutter test test/widget_test.dart
Pop-Location

Write-Host ""
Write-Host "=== Web package unit smoke ==="
Push-Location $here
if (-not (Test-Path 'assets')) { & (Join-Path $here 'setup-local.ps1') | Out-Null }
& $flutter test test/web_smoke_test.dart
Pop-Location

Write-Host ""
Write-Host "=== API + CORS probe ==="
& (Join-Path $here 'verify-api-web.ps1') @args

Write-Host ""
Write-Host "=== Manual browser QA: see SMOKE_CHECKLIST.txt ==="
