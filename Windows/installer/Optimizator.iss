; =====================================================================
;  Optimizator — інсталер для Windows 10/11 (Inno Setup 6.3+)
;  Збирається скриптом Windows\build-installer.bat або GitHub Actions.
; =====================================================================

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName    "Optimizator"
#define AppExe     "Optimizator.exe"
#define AppId      "{{B7E3C1A4-5F2D-4E8B-9C61-0A7D3E2F4B19}"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
AppComments=Автоматичний ігровий буст і керування вентиляторами
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup

; За замовчуванням — диск D (якщо він є), інакше Program Files
DefaultDirName={code:DefaultInstallDir}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UsePreviousAppDir=yes

PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763

OutputDir=..\dist
OutputBaseFilename=Optimizator-Setup-{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes

WizardStyle=modern
WizardSizePercent=110
WizardImageFile=wizard-large-100.bmp,wizard-large-200.bmp
WizardSmallImageFile=wizard-small-100.bmp,wizard-small-200.bmp
SetupIconFile=..\Assets\app.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
CloseApplications=no
ShowLanguageDialog=auto

[Languages]
Name: "uk"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "pl"; MessagesFile: "compiler:Languages\Polish.isl"

[CustomMessages]
uk.AutoStart=Запускати Optimizator разом з Windows (у треї, чекає на гру)
en.AutoStart=Start Optimizator with Windows (in tray, waits for games)
pl.AutoStart=Uruchamiaj Optimizator razem z Windows (w zasobniku)
uk.OtherTasks=Додатково:
en.OtherTasks=Other:
pl.OtherTasks=Dodatkowo:
uk.KeepSettings=Залишити налаштування Optimizator (список ігор, вентилятори, колір)?
en.KeepSettings=Keep Optimizator settings (games list, fans, accent color)?
pl.KeepSettings=Zachować ustawienia Optimizator?

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart";   Description: "{cm:AutoStart}";        GroupDescription: "{cm:OtherTasks}"

[Files]
; Self-contained збірка: .NET встановлювати не потрібно
Source: "..\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}";  Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "schtasks.exe"; \
  Parameters: "/Create /TN ""Optimizator"" /TR ""\""{app}\{#AppExe}\"" --tray"" /SC ONLOGON /RL HIGHEST /F"; \
  Flags: runhidden waituntilterminated; Tasks: autostart
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Коректно закрити програму: схема живлення і вентилятори повертаються як було
Filename: "{app}\{#AppExe}"; Parameters: "--shutdown"; Flags: runhidden waituntilterminated; RunOnceId: "StopApp"
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""Optimizator"" /F"; Flags: runhidden waituntilterminated; RunOnceId: "DelTask"

[Code]
// GetDriveType з kernel32: 3 = DRIVE_FIXED (звичайний диск, не DVD і не флешка)
function WinGetDriveType(lpRootPathName: String): Cardinal;
  external 'GetDriveTypeW@kernel32.dll stdcall';

function DefaultInstallDir(Param: String): String;
begin
  if DirExists('D:\') and (WinGetDriveType('D:\') = 3) then
    Result := 'D:\Optimizator'
  else
    Result := ExpandConstant('{autopf}\Optimizator');
end;

procedure StopRunningApp(const Dir: String);
var
  Code: Integer;
begin
  if FileExists(Dir + '\{#AppExe}') then
    Exec(Dir + '\{#AppExe}', '--shutdown', '', SW_HIDE, ewWaitUntilTerminated, Code);
  // Запасний варіант, якщо стара версія не підтримує --shutdown
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopRunningApp(ExpandConstant('{app}'));
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Data: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if (not UninstallSilent) and (MsgBox(CustomMessage('KeepSettings'), mbConfirmation, MB_YESNO) = IDNO) then
    begin
      DeleteFile(ExpandConstant('{app}\settings.json'));
      DeleteFile(ExpandConstant('{app}\restore.json'));
      Data := ExpandConstant('{localappdata}\Optimizator');
      DelTree(Data, True, True, True);
      RemoveDir(ExpandConstant('{app}'));
    end;
  end;
end;
