; AIMS Windows installer — bundles app + VC++ runtime + Media Foundation setup.
; Build: scripts\build_windows_installer.ps1

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "AIMS"
#define MyAppPublisher "iBit Ltd"
#define MyAppExeName "aims.exe"
#define MyAppURL "https://igenhr.com"
#define SourceReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{B8E4F2A1-6C3D-4E5F-9A0B-1D2E3F4A5B6C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
OutputDir=..\..\dist
OutputBaseFilename=AIMS-Setup-{#MyAppVersion}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: VCRedistBundled
Source: "install_media_features.ps1"; DestDir: "{app}\install"; Flags: ignoreversion
Source: "install_vcredist.ps1"; DestDir: "{app}\install"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\install\install_vcredist.ps1"" ""{tmp}\vc_redist.x64.exe"""; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Flags: waituntilterminated runhidden; Check: VCRedistBundled

Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\install\install_media_features.ps1"""; StatusMsg: "Setting up Windows Media components..."; Flags: waituntilterminated runhidden

Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent unchecked

[Code]
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

function InitializeSetup: Boolean;
begin
  Result := True;
  if MediaFoundationPresent or BundledMediaDllsInRelease then
    Exit;
  if MsgBox(
    'System Media Foundation DLLs are not installed.' + #13#10#13#10 +
    'AIMS will install bundled mf.dll, mfplat.dll, and MFReadWrite.dll with the app.' + #13#10 +
    'Setup may also try to install Windows Media components if needed.' + #13#10#13#10 +
    'Continue?',
    mbConfirmation, MB_YESNO) = IDNO then
    Result := False;
end;
