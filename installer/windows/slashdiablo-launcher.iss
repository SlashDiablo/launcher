; Inno Setup script for the SlashDiablo launcher.
;
; Build the payload first, then compile this:
;
;     .\testenv\win-dev.ps1 dist
;     iscc installer\windows\slashdiablo-launcher.iss
;
; The output lands in installer\output\.
;
; Everything under deploy\windows is packaged with a wildcard rather than being
; listed file by file. The previous Advanced Installer project enumerated all
; ~200 files explicitly and pointed at a build directory outside the repo, so it
; broke as soon as the Qt dependencies changed. Do not replace this with an
; explicit list.

#define SourceDir "..\..\deploy\windows"
#define AppExeName "slashdiablo-launcher.exe"
#define AppExe SourceDir + "\" + AppExeName

#ifexist AppExe
  ; Read the version straight out of the binary, which go generate populates
  ; from versioninfo.json, so this script never disagrees with the build.
  #define AppVersion GetVersionNumbersString(AppExe)
#else
  #error Build the payload first: .\testenv\win-dev.ps1 dist
#endif

[Setup]
AppName=SlashDiablo Launcher
AppVersion={#AppVersion}
AppPublisher=SlashDiablo
AppPublisherURL=https://slashdiablo.net
DefaultDirName={autopf}\SlashDiablo Launcher
DefaultGroupName=SlashDiablo
UninstallDisplayName=SlashDiablo Launcher
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir=..\output
OutputBaseFilename=SlashDiablo_Installer_{#AppVersion}
SetupIconFile=..\..\icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The launcher itself requires administrator (it writes the DEP and
; compatibility registry keys), and the default install location is Program
; Files, so elevate for the install too.
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; Recurses the whole deploy directory: the exe, the Qt DLLs and the QML module
; trees windeployqt copies in. A missing Qt DLL only fails at runtime, so the
; wildcard is deliberate.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\SlashDiablo Launcher"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall SlashDiablo Launcher"; Filename: "{uninstallexe}"
; {userdesktop} rather than {autodesktop}: the install is machine wide, but the
; shortcut belongs to whoever installed it, not every account on the PC.
Name: "{userdesktop}\SlashDiablo Launcher"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

; No [Run] entry on the finish page. The launcher manifest requires
; administrator, so launching it from Setup either inherits Setup's elevated
; token or raises a second UAC prompt straight after the install one. Users
; start it from the Start Menu shortcut, which prompts once as normal.

[UninstallDelete]
; windeployqt writes qmlcache alongside the QML modules at runtime, which is not
; part of the install and would otherwise leave the directory behind.
Type: filesandordirs; Name: "{app}\qmlcache"
