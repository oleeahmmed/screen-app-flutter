# Build AIMS Android release APK (clean build — avoids stale UI/assets).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build_android_apk.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\build_android_apk.ps1 -ApiOrigin "https://aims.igenhr.com"
#
# Output:
#   build\app\outputs\flutter-apk\app-release.apk
#   dist\aims-android-v<version>-b<build>.apk

param(
    [string]$ApiOrigin = "https://aims.igenhr.com",
    [switch]$SkipClean
)

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
$DistDir = Join-Path $Root 'dist'
$ApkOut = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'

Write-Host "==> AIMS Android APK (v$($ver.Name)+$($ver.Build))"
Write-Host "==> API_ORIGIN=$ApiOrigin"

if (-not $SkipClean) {
    Write-Host '==> flutter clean (removes old cached UI/assets)'
    flutter clean
}

Write-Host '==> flutter pub get'
flutter pub get

Write-Host '==> flutter build apk --release'
flutter build apk --release `
    --build-name="$($ver.Name)" `
    --build-number="$($ver.Build)" `
    --dart-define="API_ORIGIN=$ApiOrigin"

if (-not (Test-Path $ApkOut)) {
    throw "Build output not found: $ApkOut"
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$Dest = Join-Path $DistDir "aims-android-v$($ver.Name)-b$($ver.Build).apk"
Copy-Item -Force $ApkOut $Dest

$sizeMb = [math]::Round((Get-Item $ApkOut).Length / 1MB, 1)
Write-Host ""
Write-Host "Done. APK size: ${sizeMb} MB"
Write-Host "  APK:  $ApkOut"
Write-Host "  Copy: $Dest"
Write-Host ""
Write-Host "Install on phone:"
Write-Host "  1. Uninstall old Aims app first (Settings > Apps > Aims > Uninstall)"
Write-Host "  2. Copy $Dest to phone and install"
Write-Host "  3. Verify version in Profile should show $($ver.Name) ($($ver.Build))"
