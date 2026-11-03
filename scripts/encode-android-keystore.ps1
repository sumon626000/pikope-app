# Copy base64 keystore to clipboard for GitHub secret ANDROID_KEYSTORE_BASE64
param(
    [string]$Path = (Join-Path $PSScriptRoot '..\android\upload-keystore.jks')
)

$Path = (Resolve-Path $Path -ErrorAction Stop).Path
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
$b64 | Set-Clipboard
Write-Host "Copied ANDROID_KEYSTORE_BASE64 to clipboard ($([math]::Round($b64.Length/1024)) KB text)."
Write-Host "GitHub → pikope-app → Settings → Secrets → New → ANDROID_KEYSTORE_BASE64"
