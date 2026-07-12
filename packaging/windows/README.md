# AIMS Windows Installer (Inno Setup)

Branded installer with license agreement, wizard logos, info pages, and modern light/dark UI.

## Build (one command)

```powershell
cd "flutter and django\screen-app-flutter"
powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1
```

Output in `dist/`:
- `AIMS-Setup-<version>.exe` — full installer
- `aims-windows-v<version>-b<build>.zip` — portable zip

## Compile installer only (after Flutter release build)

```powershell
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" "/DMyAppVersion=1.0.0" packaging\windows\aims.iss
```

## Regenerate wizard images from logo

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\generate_wizard_assets.ps1
```

**Single logo source:** `assets/branding/logo.png`  
The script syncs that logo to: setup `.exe` icon, Windows `app_icon.ico`, wizard banner/small image, `web/favicon.png`, and PWA icons.

## Packaging layout

```
packaging/windows/
  aims.iss                 ← main Inno script
  generate_wizard_assets.ps1
  assets/
    license.rtf            ← formatted Terms & Conditions
    info_before.txt        ← instructions before install
    info_after.txt         ← what to do after install
    wizard-image.bmp       ← left banner (branded)
    wizard-image-hd.bmp    ← high-DPI banner
    wizard-small.bmp       ← top-right icon
    app-icon.ico           ← setup .exe icon
  install_vcredist.ps1
  install_media_features.ps1
  redist/vc_redist.x64.exe
```

## Wizard features

| Feature | Directive / asset |
|--------|-------------------|
| License accept required | `LicenseFile=assets\license.rtf` |
| Info before / after | `InfoBeforeFile` / `InfoAfterFile` |
| Company logo banner | `WizardImageFile` |
| Small logo | `WizardSmallImageFile` |
| Setup icon | `SetupIconFile` |
| Modern UI + dark mode | `WizardStyle=modern dynamic` |
| Brand colors | `WizardBackColor` / `WizardBackColorDynamicDark` |

Forced light theme: `WizardStyle=modern light` + `WizardBackColor=white` (ignores Windows dark mode).
