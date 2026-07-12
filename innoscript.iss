; Deprecated — use packaging\windows\aims.iss
; Build: powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1
;
; This stub remains so old docs still point somewhere useful.

#define MyAppName "AIMS"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "iBit Ltd"
#define MyAppExeName "aims.exe"
#define ReleaseDir "build\windows\x64\runner\Release"

[Setup]
AppId={{B8E4F2A1-6C3D-4E5F-9A0B-1D2E3F4A5B6C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://igenhr.com
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=packaging\windows\assets\license.rtf
InfoBeforeFile=packaging\windows\assets\info_before.txt
InfoAfterFile=packaging\windows\assets\info_after.txt
WizardImageFile=packaging\windows\assets\wizard-image.bmp,packaging\windows\assets\wizard-image-hd.bmp
WizardSmallImageFile=packaging\windows\assets\wizard-small.bmp
SetupIconFile=packaging\windows\assets\app-icon.ico
WizardStyle=modern
WizardSizePercent=120
OutputDir=dist
OutputBaseFilename=AIMS-Setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent unchecked
