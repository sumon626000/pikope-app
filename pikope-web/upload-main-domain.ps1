# Upload Flutter web build to pikope.com public_html (NOT backend/admin).
# 1) .\deploy-hostinger.ps1
# 2) Copy .env.hostinger.example → .env.hostinger and fill FTP creds
# 3) .\upload-main-domain.ps1

param(
    [switch]$SkipBuild,
    [string]$SourceDir = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$envFile = Join-Path $here '.env.hostinger'
if (-not (Test-Path $envFile)) {
    Write-Error "Missing $envFile — copy .env.hostinger.example and set WEB_FTP_* from hPanel FTP."
}

function Read-EnvLine([string]$path) {
    $map = @{}
    Get-Content $path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { return }
        $k = $line.Substring(0, $i).Trim()
        $v = $line.Substring($i + 1).Trim()
        $map[$k] = $v
    }
    return $map
}

$cfg = Read-EnvLine $envFile
$hostName = $cfg['WEB_FTP_HOST']
$user = $cfg['WEB_FTP_USER']
$pass = $cfg['WEB_FTP_PASS']
$remoteRoot = $cfg['WEB_FTP_REMOTE']
if (-not $remoteRoot) { $remoteRoot = '/public_html' }
$remoteRoot = $remoteRoot.TrimEnd('/')
if (-not $hostName -or -not $user -or -not $pass) {
    Write-Error 'Set WEB_FTP_HOST, WEB_FTP_USER, WEB_FTP_PASS in .env.hostinger'
}

if (-not $SkipBuild) {
    & (Join-Path $here 'deploy-hostinger.ps1')
}

if ($SourceDir -eq '') { $SourceDir = Join-Path $here 'build\web' }
if (-not (Test-Path (Join-Path $SourceDir 'index.html'))) {
    Write-Error "No index.html in $SourceDir — run deploy-hostinger.ps1 first."
}

Write-Host "Uploading $SourceDir -> ftp://$hostName$remoteRoot/ (Flutter web only, no backend)"

function Ensure-FtpDirectory([string]$uri) {
    $req = [System.Net.FtpWebRequest]::Create($uri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
    $req.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
    $req.UsePassive = $true
    try { $null = $req.GetResponse() } catch { }
}

function Upload-FtpFile([string]$localPath, [string]$remotePath) {
    $remotePath = $remotePath.Replace('\', '/')
    $uri = "ftp://$hostName$remotePath"
    $req = [System.Net.FtpWebRequest]::Create($uri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
    $req.Credentials = New-Object System.Net.NetworkCredential($user, $pass)
    $req.UseBinary = $true
    $req.UsePassive = $true
    $bytes = [System.IO.File]::ReadAllBytes($localPath)
    $req.ContentLength = $bytes.Length
    $stream = $req.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()
    $null = $req.GetResponse()
}

$files = Get-ChildItem -Path $SourceDir -Recurse -File
$n = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
    $parts = $rel -split '[\\/]'
    $acc = $remoteRoot
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        $acc = "$acc/$($parts[$i])"
        Ensure-FtpDirectory "ftp://$hostName$acc/"
    }
    $remoteFile = "$remoteRoot/$($rel -replace '\\', '/')"
    Upload-FtpFile $f.FullName $remoteFile
    $n++
    if ($n % 25 -eq 0) { Write-Host "  $n files..." }
}

Write-Host "Done. Uploaded $n files to main domain ($remoteRoot)."
Write-Host "Admin/API stays on adminnew.pikope.com -> public_html/pikope/public (do not upload backend here)."
