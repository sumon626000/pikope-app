# Quick production/staging checks before or after web deploy.
param(
    [string]$ApiBase = '',
    [string]$WebOrigin = 'http://localhost:7357'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($ApiBase -eq '') {
    $envFile = Join-Path $root '.env'
    if (Test-Path $envFile) {
        foreach ($line in Get-Content $envFile) {
            if ($line -match '^\s*API_BASE_URL=(.+)$') {
                $ApiBase = $Matches[1].Trim().Trim('"')
                break
            }
        }
    }
}
if ($ApiBase -eq '') { $ApiBase = 'https://adminnew.pikope.com' }
$ApiBase = $ApiBase.TrimEnd('/')

Write-Host "API: $ApiBase"
Write-Host "Origin probe: $WebOrigin"
Write-Host ""

$health = Invoke-WebRequest -Uri "$ApiBase/health" -UseBasicParsing -TimeoutSec 15
Write-Host "[OK] GET /health -> $($health.StatusCode)"

$config = Invoke-RestMethod -Uri "$ApiBase/config" -TimeoutSec 15
$ws = $config.ws
if ($null -eq $ws -or "$ws" -eq '') {
    Write-Host "[WARN] /config ws is empty - web uses HTTP polling (slower but OK)"
} else {
    Write-Host "[OK] /config ws = $ws"
}

try {
    $preflight = Invoke-WebRequest -Uri "$ApiBase/health" -Method Options -Headers @{
        Origin = $WebOrigin
        'Access-Control-Request-Method' = 'GET'
    } -UseBasicParsing -TimeoutSec 15
    $acao = $preflight.Headers['Access-Control-Allow-Origin']
    if ($acao) {
        Write-Host "[OK] CORS preflight Allow-Origin: $acao"
    } else {
        Write-Host "[WARN] No Access-Control-Allow-Origin - set CORS_ORIGIN on server for web"
    }
} catch {
    Write-Host "[WARN] CORS preflight failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Done. Fix WARN before public web launch."
