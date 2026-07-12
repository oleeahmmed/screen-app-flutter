# Sync installer + web icons from the SINGLE source: assets/branding/logo.png
# Prefer: dart run flutter_launcher_icons   (then this script copies Windows ICO)
# Usage:
#   powershell -ExecutionPolicy Bypass -File packaging\windows\generate_wizard_assets.ps1

$ErrorActionPreference = 'Stop'

$PackDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent (Split-Path -Parent $PackDir)
$Assets = Join-Path $PackDir 'assets'
$LogoPath = Join-Path $Root 'assets\branding\logo.png'
$WinIco = Join-Path $Root 'windows\runner\resources\app_icon.ico'
$Favicon = Join-Path $Root 'web\favicon.png'
$WebIcons = Join-Path $Root 'web\icons'

if (-not (Test-Path $LogoPath)) { throw "Logo not found: $LogoPath" }
New-Item -ItemType Directory -Force -Path $Assets, $WebIcons | Out-Null

# Always regenerate platform icons from logo first when dart is available
Push-Location $Root
try {
    dart run flutter_launcher_icons | Out-Host
} catch {
    Write-Warning "flutter_launcher_icons skipped: $_"
}
Pop-Location

if (-not (Test-Path $WinIco)) { throw "Windows app icon missing: $WinIco" }

# Installer SetupIconFile MUST be byte-identical to Windows app icon
Copy-Item -Force $WinIco (Join-Path $Assets 'app-icon.ico')

Add-Type -AssemblyName System.Drawing
$logoImg = [System.Drawing.Bitmap]::FromFile($LogoPath)
$white = [System.Drawing.Color]::White

function Save-Bmp24([System.Drawing.Image]$img, [string]$path) {
    $clone = New-Object System.Drawing.Bitmap($img.Width, $img.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($clone)
    $g.Clear($white)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($img, 0, 0, $img.Width, $img.Height)
    $g.Dispose()
    $clone.Save($path, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $clone.Dispose()
}

function New-Banner([int]$w, [int]$h, [int]$logoSize) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear($white)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.SmoothingMode = 'HighQuality'
    $g.DrawImage($logoImg, [int](($w - $logoSize) / 2), [int](($h - $logoSize) / 2), $logoSize, $logoSize)
    $g.Dispose()
    return $bmp
}

$small = New-Banner 55 55 55
Save-Bmp24 $small (Join-Path $Assets 'wizard-small.bmp')
$small.Save((Join-Path $Assets 'wizard-small.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$small.Dispose()

$banner = New-Banner 164 314 128
Save-Bmp24 $banner (Join-Path $Assets 'wizard-image.bmp')
$banner.Save((Join-Path $Assets 'wizard-image.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$banner.Dispose()

$bannerHd = New-Banner 328 628 256
Save-Bmp24 $bannerHd (Join-Path $Assets 'wizard-image-hd.bmp')
$bannerHd.Dispose()

# Ensure favicon exists (flutter_launcher_icons web usually writes it)
if (-not (Test-Path $Favicon)) {
    $fav = New-Object System.Drawing.Bitmap(48, 48, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $fg = [System.Drawing.Graphics]::FromImage($fav)
    $fg.Clear([System.Drawing.Color]::Transparent)
    $fg.InterpolationMode = 'HighQualityBicubic'
    $fg.DrawImage($logoImg, 0, 0, 48, 48)
    $fg.Dispose()
    $fav.Save($Favicon, [System.Drawing.Imaging.ImageFormat]::Png)
    $fav.Dispose()
}

Copy-Item -Force $LogoPath (Join-Path $Root 'web\logo.png')
$logoImg.Dispose()

$h1 = (Get-FileHash $WinIco).Hash
$h2 = (Get-FileHash (Join-Path $Assets 'app-icon.ico')).Hash
if ($h1 -ne $h2) { throw 'Setup icon is not identical to Windows app icon' }

Write-Host "OK — same logo everywhere (Windows ICO == installer SetupIconFile)."
Write-Host "  Logo   : $LogoPath"
Write-Host "  App ICO: $WinIco"
Write-Host "  Setup  : $(Join-Path $Assets 'app-icon.ico')"
Write-Host "  Favicon: $Favicon"
