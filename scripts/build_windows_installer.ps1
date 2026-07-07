# Build AIMS Windows release: portable ZIP + Inno Setup installer (both in dist/).
#
# Requirements:
#   - Flutter SDK
#   - Inno Setup 6: https://jrsoftware.org/isdl.php
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1
#
# Output (dist/):
#   aims-windows-v<version>-b<build>.zip   — portable (extract and run aims.exe)
#   AIMS-Setup-<version>.exe                 — full installer with VC++ / Media setup

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Get-AppVersion {
    $line = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*' | Select-Object -First 1
    if ($line -match 'version:\s*([0-9.]+)\+([0-9]+)') {
        return @{ Name = $Matches[1]; Build = $Matches[2] }
    }
    if ($line -match 'version:\s*([0-9.]+)') {
        return @{ Name = $Matches[1]; Build = '1' }
    }
    return @{ Name = '1.0.0'; Build = '1' }
}

$ver = Get-AppVersion
$Version = $ver.Name
$ReleaseDir = Join-Path $Root 'build\windows\x64\runner\Release'
$DistDir = Join-Path $Root 'dist'
$RedistDir = Join-Path $Root 'packaging\windows\redist'
$VcRedist = Join-Path $RedistDir 'vc_redist.x64.exe'
$VcRedistUrl = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
$IssFile = Join-Path $Root 'packaging\windows\aims.iss'
$ZipOut = Join-Path $DistDir "aims-windows-v$Version-b$($ver.Build).zip"

Write-Host "==> AIMS Windows build (v$Version+$($ver.Build))"

Write-Host '==> flutter build windows --release'
flutter build windows --release
if (-not (Test-Path (Join-Path $ReleaseDir 'aims.exe'))) {
    throw "Build output not found: $ReleaseDir\aims.exe"
}

New-Item -ItemType Directory -Force -Path $RedistDir, $DistDir | Out-Null

Write-Host '==> Creating portable ZIP...'
if (Test-Path $ZipOut) { Remove-Item $ZipOut -Force }
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipOut -Force
$zipMb = [math]::Round((Get-Item $ZipOut).Length / 1MB, 1)
Write-Host "    ZIP: $ZipOut (${zipMb} MB)"

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

$InstallerOut = Join-Path $DistDir "AIMS-Setup-$Version.exe"
if (-not (Test-Path $InstallerOut)) {
    throw "Expected installer not found: $InstallerOut"
}
$instMb = [math]::Round((Get-Item $InstallerOut).Length / 1MB, 1)

Write-Host ''
Write-Host 'Done. dist/ outputs:'
Write-Host "  Portable ZIP : $ZipOut (${zipMb} MB)"
Write-Host "  Installer    : $InstallerOut (${instMb} MB)"
Write-Host ''
Write-Host 'ZIP    — extract and run aims.exe (no install)'
Write-Host 'Installer — setup with VC++ Runtime + Windows Media components if needed'
