# Build Windows (ZIP + installer) and Android APK — all outputs in dist/.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -SkipClean
#   powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -ApiOrigin "https://aims.igenhr.com"
#
# Output (dist/):
#   aims-windows-v<version>-b<build>.zip
#   AIMS-Setup-<version>.exe
#   aims-android-v<version>-b<build>.apk

param(
    [string]$ApiOrigin = "https://aims.igenhr.com",
    [switch]$SkipClean
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$DistDir = Join-Path $Root 'dist'

Write-Host '========================================'
Write-Host '  AIMS release build (Windows + Android)'
Write-Host '========================================'
Write-Host ''

Write-Host '==> [1/2] Windows (ZIP + installer)'
& (Join-Path $ScriptDir 'build_windows_installer.ps1')

Write-Host ''
Write-Host '==> [2/2] Android APK'
$androidScript = Join-Path $ScriptDir 'build_android_apk.ps1'
if ($SkipClean) {
    & $androidScript -ApiOrigin $ApiOrigin -SkipClean
} else {
    & $androidScript -ApiOrigin $ApiOrigin
}

Write-Host ''
Write-Host '========================================'
Write-Host '  Done — dist/ outputs:'
Write-Host '========================================'
Get-ChildItem $DistDir -File | Sort-Object Name | ForEach-Object {
    $mb = [math]::Round($_.Length / 1MB, 1)
    Write-Host ("  {0,-40} {1,6} MB" -f $_.Name, $mb)
}
