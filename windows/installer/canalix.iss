; Installateur Windows de Canalix (compile par GitHub avec Inno Setup).
#define AppVersion GetEnv("CANALIX_VERSION")
#if AppVersion == ""
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{7C2B8E51-3A4D-4F7E-9C1B-5E2A9D0C1A01}
AppName=Canalix Player
AppVersion={#AppVersion}
AppPublisher=Canalix
AppPublisherURL=https://maloxmusique-ux.github.io/Lecteur-IPTV/
AppSupportURL=https://maloxmusique-ux.github.io/Lecteur-IPTV/aide.html
DefaultDirName={autopf}\Canalix
DefaultGroupName=Canalix
DisableProgramGroupPage=yes
; Installation pour l'utilisateur courant : pas besoin d'etre administrateur.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..
OutputBaseFilename=Canalix-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\canalix.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Canalix"; Filename: "{app}\canalix.exe"
Name: "{group}\{cm:UninstallProgram,Canalix}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Canalix"; Filename: "{app}\canalix.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\canalix.exe"; Description: "{cm:LaunchProgram,Canalix}"; Flags: nowait postinstall skipifsilent
