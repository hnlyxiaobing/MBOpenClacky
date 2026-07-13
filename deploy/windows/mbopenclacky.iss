; ============================================================
; MBOpenClacky — Inno Setup installer script (Windows)
;
; Build:
;   1. Install Inno Setup (https://jrsoftware.org/isdl.php)
;   2. Build the native binary:
;        moon build --target native --release cmd
;      The artifact is _build/native/release/build/cmd/cmd.exe
;   3. Copy cmd.exe into deploy/windows/bin/ (or set Source accordingly)
;   4. Compile this script with ISCC:
;        iscc deploy/windows/mbopenclacky.iss
;
; Result: an unsigned installer mbopenclacky-setup-x.y.z.exe
; ============================================================

#define MyAppName "MBOpenClacky"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "MBOpenClacky Contributors"
#define MyAppURL "https://github.com/hnlyxiaobing/MBOpenClacky"
#define MyAppExeName "cmd.exe"

[Setup]
AppId={{8F3C2A1B-7E59-4D2A-9C1E-2B6F5A0C9D3}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; Per-user install — no admin required, no shared-system writes.
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64
OutputDir=deploy/windows/out
OutputBaseFilename={#MyAppName}-setup-{#MyAppVersion}
SetupIconFile=
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Dependencies are declared (not bundled): native build requires the
; Visual C++ Redistributable (for MSVC-linked binary) and a C toolchain
; is NOT required at runtime. We surface the runtime dependency below.
; Signing/notarization is intentionally out of scope for this release.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
; The built native binary (named cmd.exe by the build system).
Source: "deploy\windows\bin\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; Rename to a friendlier name on install.
; (handled via a post-install rename in [Run] / a copied wrapper)

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "server"; WorkingDir: "{userappdata}\.mbopenclacky"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "server"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"

[Run]
; Create a friendly alias 'mbopenclacky.exe' -> cmd.exe so users can run
; `mbopenclacky server` from anywhere after adding {app} to PATH.
Filename: "{cmd}"; Parameters: "/c copy /Y ""{app}\{#MyAppExeName}"" ""{app}\mbopenclacky.exe"""; StatusMsg: "Creating mbopenclacky.exe alias..."
; Optionally add {app} to the user PATH.
Filename: "{cmd}"; Parameters: "/c powershell -NoProfile -Command ""[Environment]::SetEnvironmentVariable('Path', (([Environment]::GetEnvironmentVariable('Path','User') -split ';' | Where-Object { $_ -ne '{app}' }) + '{app}') -join ';', 'User')"""; StatusMsg: "Adding install dir to user PATH..."

[Registry]
; Declare the VC++ runtime dependency hint (informational; not enforced).
Root: HKCU; Subkey: "Software\{#MyAppName}"; ValueType: string; ValueName: "RequiresVCRedist"; ValueData: "14"; Flags: uninsdeletekey

[UninstallDelete]
Type: files; Name: "{app}\mbopenclacky.exe"
