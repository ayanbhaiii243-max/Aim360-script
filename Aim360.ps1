# Aim360.ps1
# Run: .\Aim360.ps1

param(
    [string]$Token = "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",
    [string]$Repo  = "ayanbhaiii243-max/Aim360",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"
$tempRoot = Join-Path $env:TEMP "Aim360"
$zipPath  = Join-Path $env:TEMP "Aim360_dl.zip"

# wipe old folder completely
if (Test-Path $tempRoot) {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$headers = @{
    "Authorization" = "Bearer $Token"
    "Accept"        = "application/vnd.github+json"
    "User-Agent"    = "Aim360-Launcher"
}

# direct archive download (private repo works with token)
$archiveUrl = "https://api.github.com/repos/$Repo/zipball/$Branch"

Invoke-WebRequest -Uri $archiveUrl -Headers $headers -OutFile $zipPath -UseBasicParsing

# extract
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

# github zipball extracts into a folder like ayanbhaiii243-max-Aim360-xxxxx
$inner = Get-ChildItem -Path $tempRoot -Directory | Select-Object -First 1
if ($inner) {
    # move everything up one level
    Get-ChildItem -Path $inner.FullName | Move-Item -Destination $tempRoot -Force
    Remove-Item $inner.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

# find Aim360.exe
$srcExe = Get-ChildItem -Path $tempRoot -Recurse -Filter "Aim360.exe" | Select-Object -First 1
if (-not $srcExe) {
    $srcExe = Get-ChildItem -Path $tempRoot -Recurse -Filter "*.exe" |
              Where-Object { $_.Name -notmatch "onnx|runtime" } |
              Select-Object -First 1
}

if (-not $srcExe) {
    Write-Error "No Aim360.exe found. Check repo has the exe + folders on main branch."
    exit 1
}

# random unique name every run
function New-RandomName {
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $len   = Get-Random -Minimum 8 -Maximum 12
    $name  = -join ((1..$len) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return "$name.exe"
}

$newName = New-RandomName
$destExe = Join-Path $srcExe.DirectoryName $newName
Move-Item -Path $srcExe.FullName -Destination $destExe -Force

Write-Host "Ready: $destExe"
Start-Process -FilePath $destExe -WorkingDirectory $srcExe.DirectoryName
return $destExe