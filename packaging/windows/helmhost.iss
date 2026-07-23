; Helmhost Windows installer (Inno Setup 6)
; Same AppId → upgradeable in-place when installing a newer VERSION.
; Build: ISCC.exe /DMyAppVersion=0.1.0 /DMyAppChannel=stable /DMySourceDir=... /DMyOutDir=... helmhost.iss

#ifndef MyAppVersion
  #define MyAppVersion "0.1.0"
#endif
#ifndef MyAppChannel
  #define MyAppChannel "stable"
#endif
#ifndef MySourceDir
  #define MySourceDir "..\..\apps\client\build\windows\x64\runner\Release"
#endif
#ifndef MyOutDir
  #define MyOutDir "..\..\dist\stable"
#endif

#define MyAppName "Helmhost"
#define MyAppPublisher "BackBenchDevs"
#define MyAppURL "https://github.com/BackBenchDevs/helmhost"
#define MyAppExeName "helmhost.exe"

[Setup]
; Fixed GUID — do not change (enables upgrades).
AppId={{A7C3E9F1-4B2D-4E8A-9C1F-6D5B8A0E2F34}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#MyOutDir}
OutputBaseFilename=helmhost-{#MyAppChannel}-windows-x64-v{#MyAppVersion}-setup
SetupIconFile=..\..\apps\client\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
LicenseFile=..\..\LICENSE
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductName={#MyAppName}
; Replace previous install of the same AppId.
UsePreviousAppDir=yes
AllowNoIcons=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
