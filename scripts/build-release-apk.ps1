# Builds a release APK with API_BASE_URL from .env (see .env.example).
# Usage: .\scripts\build-release-apk.ps1
$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot ".."))
$flutter = "C:\Users\sumon\Downloads\flutter_windows_3.44.5-stable\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
    $flutter = "$env:LOCALAPPDATA\flutter\bin\flutter.bat"
}
if (-not (Test-Path $flutter)) {
    throw "flutter.bat not found - install Flutter or edit path in this script."
}
if (-not (Test-Path ".env")) {
    throw "Missing .env - copy .env.example and set API_BASE_URL."
}
& $flutter pub get
# Universal (fat) APK: all ABIs in one file - works on 32/64-bit phones and x64 devices.
# Do not use --split-per-abi unless you ship separate APKs per architecture.
& $flutter build apk --release --dart-define-from-file=.env `
  --target-platform android-arm,android-arm64,android-x64
$out = "build\app\outputs\flutter-apk\app-release.apk"
$dest = "build\app\outputs\flutter-apk\pikope-release-universal.apk"
Copy-Item $out $dest -Force
$ver = (Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value.Trim()
$dl = Join-Path $env:USERPROFILE "Downloads\pikope-$($ver -replace '\+','-build')-universal.apk"
Copy-Item $out $dl -Force
Write-Host "Built: $((Resolve-Path $dest).Path)"
Write-Host "Copy:  $dl"
