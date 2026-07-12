; =============================================================================
; AIMS Windows Installer — Inno Setup 6.7+
; Brand: iBit Ltd / igenhr.com  |  Theme: pure white modern (forced light)
;
; Build (recommended):
;   powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1
;
; Or after `flutter build windows --release`:
;   & "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" "/DMyAppVersion=1.0.0" packaging\windows\aims.iss
;
; Regenerate wizard images from logo:
;   powershell -ExecutionPolicy Bypass -File packaging\windows\generate_wizard_assets.ps1
; =============================================================================

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "AIMS"
#define MyAppPublisher "iBit Ltd"
#define MyAppExeName "aims.exe"
#define MyAppURL "https://igenhr.com"
#define MyAppSupportURL "https://igenhr.com"
#define SourceReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{B8E4F2A1-6C3D-4E5F-9A0B-1D2E3F4A5B6C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppSupportURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
AllowNoIcons=yes
; --- License & guidance pages ---
LicenseFile=assets\license.rtf
InfoBeforeFile=assets\info_before.txt
InfoAfterFile=assets\info_after.txt
; --- Branding: same logo as app (from flutter_launcher_icons → app_icon.ico) ---
WizardImageFile=assets\wizard-image.bmp,assets\wizard-image-hd.bmp
WizardSmallImageFile=assets\wizard-small.bmp
SetupIconFile=assets\app-icon.ico
; app-icon.ico is a byte-copy of windows\runner\resources\app_icon.ico (logo.png)
; --- Pure white modern UI (forced light — ignores Windows dark mode) ---
WizardStyle=modern light
WizardSizePercent=120
WizardImageStretch=yes
WizardBackColor=white
WizardImageBackColor=white
ShowLanguageDialog=no
; --- Output ---
OutputDir=..\..\dist
OutputBaseFilename=AIMS-Setup-{#MyAppVersion}
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
VersionInfoCopyright=Copyright (C) 2024-2026 {#MyAppPublisher}
; --- Compression & platform ---
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SetupAppTitle=AIMS Setup
SetupWindowTitle=AIMS {#MyAppVersion} — Setup
WelcomeLabel1=Welcome to [name] Setup
WelcomeLabel2=This will install [name/ver] on your computer.%n%nAIMS brings attendance, tasks, screen activity, chat, and reports together for your team.%n%nIt is recommended that you close all other applications before continuing.
FinishedLabel=Setup has finished installing [name] on your computer. You can launch AIMS now or later from the Start Menu.
LicenseLabel=Please read the following License Agreement. You must accept it before installing AIMS.
InfoBeforeLabel=Please read the following important information before continuing.
InfoAfterClickLabel=Please read the following information, then click Finish to exit Setup.
SelectDirLabel3=Setup will install AIMS into the following folder.
SelectDirBrowseLabel=To continue, click Next. If you would like to select a different folder, click Browse.
BeveledLabel=iBit Ltd  ·  igenhr.com

[Tasks]
Name: "desktopicon"; Description: "Create a &Desktop shortcut"; GroupDescription: "Additional icons:"; Flags: checkedonce

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall skipifsourcedoesntexist
Source: "install_media_features.ps1"; DestDir: "{app}\install"; Flags: ignoreversion
Source: "install_vcredist.ps1"; DestDir: "{app}\install"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Comment: "Open AIMS"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Comment: "Open AIMS"; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\install\install_vcredist.ps1"" ""{tmp}\vc_redist.x64.exe"""; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Flags: waituntilterminated runhidden; Check: VCRedistBundled
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\install\install_media_features.ps1"""; StatusMsg: "Setting up Windows Media components..."; Flags: waituntilterminated runhidden
Filename: "{app}\{#MyAppExeName}"; Description: "Launch AIMS now"; Flags: nowait postinstall skipifsilent unchecked

[Code]
const
  (* Light theme text — navy / slate on pure white *)
  C_Title    = $2A170F;   (* near #0F172A *)
  C_Heading  = $AE5A1E;   (* #1E3AAE-ish navy *)
  C_Body     = $685547;   (* slate *)
  C_Accent   = $F6823B;   (* primary blue #3B82F6 as BGR *)
  C_White    = $FFFFFF;

var
  BrandBanner: TPanel;
  BrandLabel: TNewStaticText;

function VCRedistBundled: Boolean;
begin
  Result := FileExists(ExpandConstant('{tmp}\vc_redist.x64.exe'));
end;

function MediaFoundationPresent: Boolean;
begin
  Result :=
    FileExists(ExpandConstant('{sys}\mf.dll')) and
    FileExists(ExpandConstant('{sys}\MFPlat.DLL')) and
    FileExists(ExpandConstant('{sys}\MFReadWrite.dll'));
end;

function BundledMediaDllsInRelease: Boolean;
begin
  Result :=
    FileExists(ExpandConstant('{#SourceReleaseDir}\mf.dll')) and
    FileExists(ExpandConstant('{#SourceReleaseDir}\mfplat.dll')) and
    FileExists(ExpandConstant('{#SourceReleaseDir}\MFReadWrite.dll'));
end;

procedure ApplyBrandTypography;
begin
  WizardForm.PageNameLabel.Font.Color := C_Title;
  WizardForm.PageNameLabel.Font.Style := [fsBold];
  WizardForm.PageDescriptionLabel.Font.Color := C_Body;

  WizardForm.WelcomeLabel1.Font.Color := C_Title;
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.WelcomeLabel2.Font.Color := C_Body;

  WizardForm.FinishedLabel.Font.Color := C_Body;
  WizardForm.FinishedHeadingLabel.Font.Color := C_Title;
  WizardForm.FinishedHeadingLabel.Font.Style := [fsBold];

  if Assigned(WizardForm.WizardSmallBitmapImage) then
    WizardForm.WizardSmallBitmapImage.BackColor := C_White;

  WizardForm.NextButton.Default := True;
end;

procedure CreateBrandFooter;
begin
  BrandBanner := TPanel.Create(WizardForm);
  BrandBanner.Parent := WizardForm;
  BrandBanner.Height := ScaleY(3);
  BrandBanner.Align := alBottom;
  BrandBanner.BevelOuter := bvNone;
  BrandBanner.Color := C_Accent;
  BrandBanner.ParentBackground := False;

  BrandLabel := TNewStaticText.Create(WizardForm);
  BrandLabel.Parent := WizardForm;
  BrandLabel.Caption := 'AIMS  ·  iBit Ltd  ·  igenhr.com';
  BrandLabel.Font.Name := 'Segoe UI';
  BrandLabel.Font.Size := 8;
  BrandLabel.Font.Color := C_Body;
  BrandLabel.AutoSize := True;
  BrandLabel.Left := ScaleX(12);
  BrandLabel.Top := WizardForm.ClientHeight - ScaleY(42);
  BrandLabel.Anchors := [akLeft, akBottom];
end;

procedure InitializeWizard;
begin
  ApplyBrandTypography;
  CreateBrandFooter;
  WizardForm.LicenseAcceptedRadio.Checked := False;
  WizardForm.LicenseNotAcceptedRadio.Checked := True;
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  if MediaFoundationPresent or BundledMediaDllsInRelease then
    Exit;
  if MsgBox(
    'System Media Foundation components were not detected.' + #13#10#13#10 +
    'AIMS will install bundled media DLLs with the app when available.' + #13#10 +
    'Setup may also configure Windows Media features if needed.' + #13#10#13#10 +
    'Continue with installation?',
    mbConfirmation, MB_YESNO) = IDNO then
    Result := False;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  case CurPageID of
    wpWelcome:
      WizardForm.NextButton.Caption := 'Get Started >';
    wpLicense:
      WizardForm.NextButton.Caption := 'I Accept >';
    wpFinished:
      WizardForm.NextButton.Caption := 'Finish';
  else
    WizardForm.NextButton.Caption := SetupMessage(msgButtonNext);
  end;
end;
