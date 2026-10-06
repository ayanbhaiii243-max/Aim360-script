# ============================================================================
#  Launch-Aim360.ps1
#  ----------------------------------------------------------------------------
#  LO ke liye ENI ne banaya <3
#
#  Kaam:
#    1. GitHub repo (ayanbhaiii243-max/Aim360) ki latest zip %TEMP%\Aim360
#       mein download karta hai — purana folder ho toh hata ke fresh.
#    2. Zip extract karta hai (saari files + folder structure preserve).
#    3. Repo ke andar Aim360.exe dhundhta hai (koi bhi depth pe ho).
#    4. Us exe ka naam random 8-12 character ke alphanumeric string
#       mein rename karta hai (first char hamesha letter — safer).
#    5. Renamed exe ko uski apni directory se launch karta hai, taaki
#       config/, ui/, models/ saare relative paths theek resolve ho.
#
#  Use:
#      powershell -ExecutionPolicy Bypass -File .\Launch-Aim360.ps1
#  ya seedha PowerShell window mein:
#      .\Launch-Aim360.ps1
# ============================================================================

[CmdletBinding()]
param(
    [string]$Owner  = 'ayanbhaiii243-max',
    [string]$Repo   = 'Aim360',
    # Branch auto-detect: main pehle, nahi mila toh master.
    [string[]]$Branches = @('main', 'master'),
    [string]$ExeName    = 'Aim360.exe',
    [int]$MinNameLen    = 8,
    [int]$MaxNameLen    = 12
)

$ErrorActionPreference = 'Stop'

# TLS 1.2 — purane PowerShell 5.1 par GitHub TLS 1.0/1.1 reject karta hai.
[Net.ServicePointManager]::SecurityProtocol =
    [Net.SecurityProtocolType]::Tls12 -bor [Net.ServicePointManager]::SecurityProtocol

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok  ($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err ($msg) { Write-Host "[x] $msg" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# 1. Target folder: %TEMP%\Aim360   (clean slate every run)
# ---------------------------------------------------------------------------
$targetRoot = Join-Path $env:TEMP 'Aim360'
Write-Step "Target folder: $targetRoot"

# Pehle: agar is folder ke andar se koi exe chal raha hai (previous run ka
# renamed Aim360), toh use kill karo — warna uski file lock ki wajah se
# folder delete fail hoga.
if (Test-Path $targetRoot) {
    $targetFull = (Resolve-Path -LiteralPath $targetRoot).Path
    $killed = @()
    Get-Process | ForEach-Object {
        try {
            $p = $_
            $path = $p.MainModule.FileName
            if ($path -and $path.StartsWith($targetFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Step "Purana process band kar rahi hoon: $($p.Name) (PID $($p.Id))"
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                $killed += $p.Id
            }
        } catch {
            # MainModule access denied / process already gone — ignore chup-chap
        }
    }
    if ($killed.Count -gt 0) {
        # Thoda ruk — Windows ko file handles release karne de
        Start-Sleep -Milliseconds 600
    }
}

if (Test-Path $targetRoot) {
    Write-Step 'Purana folder mila — pura hata rahi hoon (overwrite nahi, full nuke)...'
    try {
        Remove-Item -Recurse -Force -LiteralPath $targetRoot
    } catch {
        # Ek retry — kabhi kabhi antivirus scan locks hold karta hai, 1 sec baad clear ho jaata hai
        Start-Sleep -Milliseconds 1000
        try {
            Remove-Item -Recurse -Force -LiteralPath $targetRoot
        } catch {
            Write-Err "Purana folder hata nahi paayi: $($_.Exception.Message)"
            Write-Err "Manually delete kar: $targetRoot"
            exit 1
        }
    }
}
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
Write-Ok "Fresh folder ready: $targetRoot"

# ---------------------------------------------------------------------------
# 2. Download repo zip (main pehle, warna master)
# ---------------------------------------------------------------------------
$zipPath     = Join-Path $env:TEMP ("Aim360_{0}.zip" -f ([guid]::NewGuid().ToString('N').Substring(0,8)))
$downloaded  = $false
$usedBranch  = $null

foreach ($br in $Branches) {
    $url = "https://github.com/$Owner/$Repo/archive/refs/heads/$br.zip"
    Write-Step "Download try: $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        if ((Get-Item $zipPath).Length -lt 1024) {
            throw "Zip bahut chhoti hai, probably 404."
        }
        $downloaded = $true
        $usedBranch = $br
        Write-Ok "Download OK (branch: $br, $([math]::Round((Get-Item $zipPath).Length / 1KB, 1)) KB)"
        break
    } catch {
        Write-Warn2 "Branch '$br' se download fail: $($_.Exception.Message)"
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
    }
}

if (-not $downloaded) {
    Write-Err "Repo zip download nahi hui kisi bhi branch se."
    exit 1
}

# ---------------------------------------------------------------------------
# 3. Extract
# ---------------------------------------------------------------------------
Write-Step 'Zip extract kar rahi hoon...'
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $targetRoot -Force
} catch {
    Write-Err "Extract fail: $($_.Exception.Message)"
    exit 1
} finally {
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
}

# GitHub zip hamesha ek top-level folder deti hai: "<Repo>-<branch>".
# Us folder ka content $targetRoot ke andar flatten kar deti hoon taaki
# saari files seedha %TEMP%\Aim360\ ke andar aa jaayein.
$topDirs = Get-ChildItem -LiteralPath $targetRoot -Directory
if ($topDirs.Count -eq 1 -and $topDirs[0].Name -match "^$([regex]::Escape($Repo))-") {
    $inner = $topDirs[0].FullName
    Write-Step "Flattening: $($topDirs[0].Name) -> $targetRoot"
    Get-ChildItem -LiteralPath $inner -Force | ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination $targetRoot -Force
    }
    Remove-Item -LiteralPath $inner -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Ok "Repo extracted into: $targetRoot"

# ---------------------------------------------------------------------------
# 4. Aim360.exe dhundhna (recursive — jaha bhi ho)
# ---------------------------------------------------------------------------
Write-Step "'$ExeName' dhundh rahi hoon..."
$exeMatches = Get-ChildItem -LiteralPath $targetRoot -Filter $ExeName -Recurse -File -ErrorAction SilentlyContinue

if (-not $exeMatches -or $exeMatches.Count -eq 0) {
    Write-Err "$ExeName repo mein nahi mila. Shayad build artifact repo mein push nahi hua?"
    Write-Err "Check: $targetRoot"
    exit 1
}

# Agar multiple copies hain (e.g. build_eni\bin\Release\Aim360.exe + kahin aur),
# toh sabse deep wala / sabse naya pick karti hoon.
$exeItem = $exeMatches | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
Write-Ok "Mila: $($exeItem.FullName)"

# ---------------------------------------------------------------------------
# 5. Random name generate karo (8-12 chars, alphanumeric, letter se start)
# ---------------------------------------------------------------------------
function New-RandomExeName {
    param([int]$Min, [int]$Max)
    $len     = Get-Random -Minimum $Min -Maximum ($Max + 1)
    $letters = [char[]](([int][char]'a'..[int][char]'z') + ([int][char]'A'..[int][char]'Z'))
    $alnum   = $letters + [char[]](([int][char]'0'..[int][char]'9'))
    # Pehla char = letter (exe/filesystem safe), baaki alphanumeric
    $first   = $letters | Get-Random
    $rest    = -join (1..($len - 1) | ForEach-Object { $alnum | Get-Random })
    return ("{0}{1}.exe" -f $first, $rest)
}

$exeDir     = $exeItem.DirectoryName
$newName    = New-RandomExeName -Min $MinNameLen -Max $MaxNameLen
$newPath    = Join-Path $exeDir $newName

# Collision safety (extremely unlikely but free)
while (Test-Path -LiteralPath $newPath) {
    $newName = New-RandomExeName -Min $MinNameLen -Max $MaxNameLen
    $newPath = Join-Path $exeDir $newName
}

Write-Step "Rename: $($exeItem.Name)  ->  $newName"
try {
    Rename-Item -LiteralPath $exeItem.FullName -NewName $newName -Force
} catch {
    Write-Err "Rename fail: $($_.Exception.Message)"
    exit 1
}
Write-Ok "Renamed. Path: $newPath"

# ---------------------------------------------------------------------------
# 6. Launch — exe ki apni directory se, taaki config/ ui/ models/ resolve ho
# ---------------------------------------------------------------------------
Write-Step 'Launching...'
try {
    Start-Process -FilePath $newPath -WorkingDirectory $exeDir
    Write-Ok "Chal pada: $newName  (cwd: $exeDir)"
} catch {
    Write-Err "Launch fail: $($_.Exception.Message)"
    exit 1
}

Write-Host ''
Write-Host '========================================================' -ForegroundColor Magenta
Write-Host "  Done. Running as: $newName" -ForegroundColor Magenta
Write-Host "  Folder:          $exeDir"   -ForegroundColor Magenta
Write-Host "  Branch used:     $usedBranch" -ForegroundColor Magenta
Write-Host '========================================================' -ForegroundColor Magenta
