# Builds a release APK with API_BASE_URL from .env (see .env.example).
# Usage: .\scripts\build-release-apk.ps1
$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot ".."))
$flutter = "C:\Users\sumon\Downloads\flutter_windows_3.44.5-stable\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
    $flutter = "$env:LOCALAPPDATA\flutter\bin\flutter.bat"
}
if (-not (Test-Path $flutter)) {
    throw "flutter.bat not found — install Flutter or edit path in this script."
}
if (-not (Test-Path ".env")) {
    throw "Missing .env — copy .env.example and set API_BASE_URL."
}
& $flutter pub get
& $flutter build apk --release --dart-define-from-file=.env
$out = "build\app\outputs\flutter-apk\app-release.apk"
$dest = "build\app\outputs\flutter-apk\pikope-release.apk"
Copy-Item $out $dest -Force
Write-Host "Built: $((Resolve-Path $dest).Path)"
