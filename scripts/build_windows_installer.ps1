# Build Flutter Windows release + Inno Setup installer for Aims.
param(
    [string]$ApiOrigin = "https://aims.igenhr.com",
    [string]$InnoSetup = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "==> Flutter build (windows)..." -ForegroundColor Cyan
flutter build windows --release --dart-define=API_ORIGIN=$ApiOrigin
if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }

$release = Join-Path $ProjectRoot "build\windows\x64\runner\Release\aims.exe"
if (-not (Test-Path $release)) {
    throw "Release not found: $release"
}

if (-not (Test-Path $InnoSetup)) {
    throw "Inno Setup compiler not found at: $InnoSetup"
}

Write-Host "==> Inno Setup compile..." -ForegroundColor Cyan
& $InnoSetup (Join-Path $ProjectRoot "innoscript.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC failed" }

$installer = Get-ChildItem (Join-Path $ProjectRoot "installer\aims-*-setup.exe") | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host ""
Write-Host "Done: $($installer.FullName)" -ForegroundColor Green
