# Build AIMS Windows installer (Inno Setup) with VC++ + Media Foundation prerequisites.
#
# Requirements:
#   - Flutter SDK
#   - Inno Setup 6: https://jrsoftware.org/isdl.php
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Get-AppVersion {
    $line = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*' | Select-Object -First 1
    if ($line -match 'version:\s*([0-9.]+)') { return $Matches[1] }
    return '1.0.0'
}

$Version = Get-AppVersion
$ReleaseDir = Join-Path $Root 'build\windows\x64\runner\Release'
$DistDir = Join-Path $Root 'dist'
$RedistDir = Join-Path $Root 'packaging\windows\redist'
$VcRedist = Join-Path $RedistDir 'vc_redist.x64.exe'
$VcRedistUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
$IssFile = Join-Path $Root 'packaging\windows\aims.iss'

Write-Host "==> AIMS Windows installer build (v$Version)"

Write-Host '==> flutter build windows --release'
flutter build windows --release
if (-not (Test-Path (Join-Path $ReleaseDir 'aims.exe'))) {
    throw "Build output not found: $ReleaseDir\aims.exe"
}

New-Item -ItemType Directory -Force -Path $RedistDir, $DistDir | Out-Null

if (-not (Test-Path $VcRedist)) {
    Write-Host '==> Downloading Visual C++ Redistributable...'
    Invoke-WebRequest -Uri $VcRedistUrl -OutFile $VcRedist -UseBasicParsing
} else {
    Write-Host '==> VC++ redist already cached'
}

$IsccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$Iscc = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Iscc) {
    throw @"
Inno Setup 6 not found. Install from https://jrsoftware.org/isdl.php
Then re-run: powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1
"@
}

Write-Host "==> Compiling installer with Inno Setup..."
& $Iscc "/DMyAppVersion=$Version" $IssFile
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed (exit $LASTEXITCODE)" }

$Output = Join-Path $DistDir "AIMS-Setup-$Version.exe"
if (-not (Test-Path $Output)) {
    throw "Expected installer not found: $Output"
}

Write-Host ''
Write-Host 'Done.'
Write-Host "  Installer: $Output"
Write-Host ''
Write-Host 'Give this .exe to users. It installs:'
Write-Host '  - AIMS application files'
Write-Host '  - Visual C++ Runtime (if missing)'
Write-Host '  - Windows Media components via DISM (if missing)'
