; DSH-Portable 多语言安装向导（Inno Setup 7）
; 构建期工具：tools\InnoSetup7\ISCC.exe（便携解压版，不写注册表、不装服务）
;
; 用法：
;   ISCC.exe /DSOURCE_ROOT="D:\Software Installation\deepseek-harness" DSH-Portable.iss
;
; 关键设计（与实施计划 Phase 4 对应）：
;   - 无需管理员（PrivilegesRequired=lowest），仅 HKCU 级写入
;   - 中/英双语向导，写入数据目录 locale.preference（shell detectLanguage 同逻辑）
;   - 高级页自定义数据目录 -> 写 apps\desktop-shell\launcher-config.json，进程级 DSH_HOME，不改系统环境变量
;   - 桌面快捷方式 {userdesktop}（自动识别重定向/OneDrive）；创建失败跳过并写 install-log.txt
;   - 开机自启为向导选项，默认关闭；仅勾选时写 HKCU Run

#define MyAppName "DSH-Portable"
#define MyAppVersion "0.1.1-rc.2"
#define MyAppVerNum "0.1.1.2"
#define MyAppPublisher "DSH-Portable (unofficial local build)"
#define MyAppExeName "DSH-Portable.exe"
#ifndef SourceRoot
  #define SourceRoot "D:\Software Installation\deepseek-harness"
#endif
#define ElectronExe "apps\desktop-shell\node_modules\electron\dist\electron.exe"

[Setup]
AppId={{AFF08DAB-DFB3-4474-9ED0-38E83ACC6521}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
VersionInfoVersion={#MyAppVerNum}
VersionInfoDescription={#MyAppName} Setup
DefaultDirName=D:\Software Installation\DSH-Portable
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename=DSH-Portable-Setup-{#MyAppVersion}
Compression=none
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=yes
LicenseFile=license.txt
CloseApplications=no
SetupLogging=yes
UninstallDisplayName={#MyAppName} {#MyAppVersion}
UninstallDisplayIcon={app}\{#ElectronExe}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Files]
Source: "{#SourceRoot}\src.7z"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\7zr.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\runtime\*"; DestDir: "{app}\runtime"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\apps\desktop-shell\*"; DestDir: "{app}\apps\desktop-shell"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "launcher-config.json,install-log.txt"
Source: "{#SourceRoot}\packages\*"; DestDir: "{app}\packages"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\scripts\windows\*"; DestDir: "{app}\scripts\windows"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\scripts\stop-dsh.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "{#SourceRoot}\scripts\clean-dsh.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "{#SourceRoot}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\upstream-lock.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\version-manifest.json"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "{app}\{#ElectronExe}"; Parameters: """{app}\apps\desktop-shell"""; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\apps\desktop-shell\launcher-config.json"
Type: files; Name: "{app}\install-log.txt"
Type: filesandordirs; Name: "{app}\src"
Type: files; Name: "{app}\src.7z"

[Code]
var
  OptionsPage: TWizardPage;
  AdvancedPage: TWizardPage;
  DesktopCheck: TNewCheckBox;
  StartMenuCheck: TNewCheckBox;
  AutoStartCheck: TNewCheckBox;
  DataDirEdit: TNewEdit;
  DataDirBrowseBtn: TNewButton;
  DataDirLabel: TNewStaticText;
  SsdHintLabel: TNewStaticText;
  PageInitDone: Boolean;

const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';

function HasParam(const Name: String): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if UpperCase(ParamStr(i)) = UpperCase(Name) then
    begin
      Result := True;
      Exit;
    end;
end;

function GetParamValue(const Prefix: String): String;
var
  i: Integer;
  p, up: String;
begin
  Result := '';
  for i := 1 to ParamCount do
  begin
    p := ParamStr(i);
    up := UpperCase(p);
    if Pos(UpperCase(Prefix), up) = 1 then
    begin
      Result := Copy(p, Length(Prefix) + 1, Length(p));
      Exit;
    end;
  end;
end;

function GetDefaultDataDir: String;
var
  appdata: String;
begin
  appdata := RemoveBackslash(ExpandConstant('{userappdata}'));
  Result := ExtractFilePath(RemoveBackslash(ExtractFilePath(appdata))) + '.dsh';
end;

function NormalizeDir(S: String): String;
begin
  Result := RemoveBackslash(Trim(S));
end;

function IsChinese: Boolean;
begin
  Result := ActiveLanguage() = 'chinesesimp';
end;

procedure AppendInstallLog(Msg: String);
var
  LogPath: String;
begin
  LogPath := ExpandConstant('{app}\install-log.txt');
  try
    SaveStringToFile(LogPath, Msg + #13#10, True);
  except
    Log('install-log write failed: ' + Msg);
  end;
end;

procedure CreateShortcut(ShortcutPath, Target, Params, WorkDir, IconPath: String);
var
  Shell: Variant;
  Lnk: Variant;
begin
  try
    Shell := CreateOleObject('WScript.Shell');
    Lnk := Shell.CreateShortcut(ShortcutPath);
    Lnk.TargetPath := Target;
    Lnk.Arguments := Params;
    Lnk.WorkingDirectory := WorkDir;
    if IconPath <> '' then
      Lnk.IconLocation := IconPath + ',0';
    Lnk.Save;
    AppendInstallLog('[shortcut] created: ' + ShortcutPath);
  except
    AppendInstallLog('[shortcut] FAILED to create: ' + ShortcutPath + ' (' + GetExceptionMessage + ')');
  end;
end;

procedure CreateShortcuts;
var
  AppDir, Electron, Params, DesktopPath, StartMenuDir: String;
begin
  AppDir := ExpandConstant('{app}');
  Electron := AppDir + '\{#ElectronExe}';
  Params := 'apps\desktop-shell';

  if DesktopCheck.Checked then
  begin
    DesktopPath := ExpandConstant('{userdesktop}\{#MyAppName}.lnk');
    try
      CreateShortcut(DesktopPath, Electron, Params, AppDir, Electron);
      if FileExists(DesktopPath) then
        Log('[shortcut] desktop: ' + DesktopPath)
      else
        AppendInstallLog('[shortcut] desktop skipped: ' + DesktopPath);
    except
      AppendInstallLog('[shortcut] desktop failed: ' + DesktopPath + ' (' + GetExceptionMessage + ')');
    end;
  end;

  if StartMenuCheck.Checked then
  begin
    StartMenuDir := ExpandConstant('{userprograms}\{#MyAppName}');
    ForceDirectories(StartMenuDir);
    CreateShortcut(StartMenuDir + '\{#MyAppName}.lnk', Electron, Params, AppDir, Electron);
    if FileExists(StartMenuDir + '\{#MyAppName}.lnk') then
      Log('[shortcut] startmenu: ' + StartMenuDir)
    else
      AppendInstallLog('[shortcut] startmenu skipped: ' + StartMenuDir);
  end;
end;

procedure SetAutoStart(Enable: Boolean);
var
  AppDir: String;
begin
  if Enable then
  begin
    AppDir := ExpandConstant('{app}');
    RegWriteStringValue(HKCU, RunKey, '{#MyAppName}',
      '"' + AppDir + '\{#ElectronExe}" "' + AppDir + '\apps\desktop-shell"');
    Log('[autostart] enabled');
  end
  else
  begin
    RegDeleteValue(HKCU, RunKey, '{#MyAppName}');
    Log('[autostart] disabled');
  end;
end;

procedure WriteLauncherConfig(DataDir: String);
var
  ConfigPath, JsonData: String;
begin
  if NormalizeDir(DataDir) = '' then
    JsonData := ''
  else
    JsonData := DataDir;
  StringChangeEx(JsonData, '\', '\\', False);
  ConfigPath := ExpandConstant('{app}\apps\desktop-shell\launcher-config.json');
  SaveStringToFile(ConfigPath,
    '{' + #13#10 + '  "dataDir": "' + JsonData + '"' + #13#10 + '}' + #13#10, False);
  Log('[config] launcher-config.json dataDir=' + DataDir);
end;

procedure WriteLocalePreference(DataDir: String);
var
  Pref, LocalePath: String;
begin
  if IsChinese then
    Pref := 'zh'
  else
    Pref := 'en';
  ForceDirectories(DataDir);
  LocalePath := NormalizeDir(DataDir) + '\locale.preference';
  SaveStringToFile(LocalePath, Pref + #13#10, False);
  Log('[locale] wrote ' + LocalePath + ' = ' + Pref);
end;

procedure UpdateOptionsPageLabels;
begin
  if PageInitDone then Exit;
  if IsChinese then
  begin
    OptionsPage.Caption := '选项';
    OptionsPage.Description := '选择要创建的快捷方式与启动方式。';
    DesktopCheck.Caption := '创建桌面快捷方式（默认）';
    StartMenuCheck.Caption := '创建开始菜单快捷方式';
    AutoStartCheck.Caption := '开机自动启动（默认关闭；仅当前用户，不装服务）';
    AdvancedPage.Caption := '高级：数据目录';
    AdvancedPage.Description := '设置配置、凭据与审计日志的存放位置。';
    DataDirLabel.Caption := '数据目录（进程级 DSH_HOME，不修改系统环境变量）：';
    DataDirBrowseBtn.Caption := '浏览...';
    SsdHintLabel.Caption := '提示：建议将程序安装在 SSD 上以获得最佳性能。';
  end
  else
  begin
    OptionsPage.Caption := 'Options';
    OptionsPage.Description := 'Choose which shortcuts and startup behavior to create.';
    DesktopCheck.Caption := 'Create a desktop shortcut (default)';
    StartMenuCheck.Caption := 'Create a Start Menu shortcut';
    AutoStartCheck.Caption := 'Start with Windows (off by default; current user only, no service)';
    AdvancedPage.Caption := 'Advanced: Data Directory';
    AdvancedPage.Description := 'Where configuration, credentials and audit logs are stored.';
    DataDirLabel.Caption := 'Data directory (process-level DSH_HOME, no system environment change):';
    DataDirBrowseBtn.Caption := 'Browse...';
    SsdHintLabel.Caption := 'Tip: an SSD is recommended for the program directory.';
  end;
  PageInitDone := True;
end;

procedure DataDirBrowseBtnClick(Sender: TObject);
var
  Dir: String;
begin
  Dir := NormalizeDir(DataDirEdit.Text);
  if Dir = '' then
    Dir := GetDefaultDataDir;
  if BrowseForFolder('Select data directory:', Dir, True) then
    DataDirEdit.Text := Dir;
end;

procedure InitializeWizard;
begin
  OptionsPage := CreateCustomPage(wpSelectDir, 'Options', '');
  DesktopCheck := TNewCheckBox.Create(OptionsPage);
  DesktopCheck.Left := ScaleX(16);
  DesktopCheck.Top := ScaleY(16);
  DesktopCheck.Width := OptionsPage.SurfaceWidth - ScaleX(32);
  DesktopCheck.Height := ScaleY(24);
  DesktopCheck.Checked := True;
  DesktopCheck.Parent := OptionsPage.Surface;

  StartMenuCheck := TNewCheckBox.Create(OptionsPage);
  StartMenuCheck.Left := DesktopCheck.Left;
  StartMenuCheck.Top := DesktopCheck.Top + ScaleY(30);
  StartMenuCheck.Width := DesktopCheck.Width;
  StartMenuCheck.Height := ScaleY(24);
  StartMenuCheck.Checked := False;
  StartMenuCheck.Parent := OptionsPage.Surface;

  AutoStartCheck := TNewCheckBox.Create(OptionsPage);
  AutoStartCheck.Left := DesktopCheck.Left;
  AutoStartCheck.Top := StartMenuCheck.Top + ScaleY(30);
  AutoStartCheck.Width := DesktopCheck.Width;
  AutoStartCheck.Height := ScaleY(24);
  AutoStartCheck.Checked := False;
  AutoStartCheck.Parent := OptionsPage.Surface;

  AdvancedPage := CreateCustomPage(OptionsPage.ID, 'Advanced: Data Directory', '');
  DataDirLabel := TNewStaticText.Create(AdvancedPage);
  DataDirLabel.Left := ScaleX(16);
  DataDirLabel.Top := ScaleY(16);
  DataDirLabel.Width := AdvancedPage.SurfaceWidth - ScaleX(32);
  DataDirLabel.Height := ScaleY(20);
  DataDirLabel.Parent := AdvancedPage.Surface;

  DataDirEdit := TNewEdit.Create(AdvancedPage);
  DataDirEdit.Left := DataDirLabel.Left;
  DataDirEdit.Top := DataDirLabel.Top + ScaleY(26);
  DataDirEdit.Width := AdvancedPage.SurfaceWidth - ScaleX(32) - ScaleX(86);
  DataDirEdit.Text := GetDefaultDataDir;
  DataDirEdit.Parent := AdvancedPage.Surface;

  DataDirBrowseBtn := TNewButton.Create(AdvancedPage);
  DataDirBrowseBtn.Left := DataDirEdit.Left + DataDirEdit.Width + ScaleX(8);
  DataDirBrowseBtn.Top := DataDirEdit.Top - ScaleY(2);
  DataDirBrowseBtn.Width := ScaleX(78);
  DataDirBrowseBtn.Height := DataDirEdit.Height + ScaleY(4);
  DataDirBrowseBtn.Caption := 'Browse...';
  DataDirBrowseBtn.OnClick := @DataDirBrowseBtnClick;
  DataDirBrowseBtn.Parent := AdvancedPage.Surface;

  SsdHintLabel := TNewStaticText.Create(WizardForm.SelectDirPage);
  SsdHintLabel.Left := WizardForm.SelectDirLabel.Left;
  SsdHintLabel.Top := WizardForm.DirEdit.Top + WizardForm.DirEdit.Height + ScaleY(10);
  SsdHintLabel.Width := WizardForm.SelectDirLabel.Width;
  SsdHintLabel.Height := ScaleY(40);
  SsdHintLabel.Parent := WizardForm.SelectDirPage;

  if GetParamValue('/DATADIR=') <> '' then
    DataDirEdit.Text := GetParamValue('/DATADIR=');
  if HasParam('/NODESKTOP') then
    DesktopCheck.Checked := False;
  if HasParam('/NOSTARTMENU') then
    StartMenuCheck.Checked := False;
  if HasParam('/NOAUTOSTART') then
    AutoStartCheck.Checked := False;

  PageInitDone := False;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = OptionsPage.ID) or (CurPageID = AdvancedPage.ID) then
    UpdateOptionsPageLabels;
end;

function ValidateDataDir: Boolean;
var
  DataDir, AppDir: String;
begin
  Result := False;
  DataDir := NormalizeDir(DataDirEdit.Text);
  if DataDir = '' then
  begin
    MsgBox('数据目录不能为空。' + #13#10 + 'Data directory must not be empty.', mbError, MB_OK);
    Exit;
  end;
  AppDir := LowerCase(NormalizeDir(ExpandConstant('{app}')));
  if LowerCase(DataDir) = AppDir then
  begin
    MsgBox('数据目录不能与程序目录相同，否则卸载会删除你的数据。' + #13#10 +
      'The data directory must differ from the program directory, otherwise uninstalling would delete your data.',
      mbError, MB_OK);
    Exit;
  end;
  Result := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = AdvancedPage.ID then
    Result := ValidateDataDir;
end;

procedure ExtractSrc;
var
  AppDir, SevenZip, Archive, Params: String;
  ResultCode: Integer;
begin
  AppDir := ExpandConstant('{app}');
  SevenZip := AppDir + '\7zr.exe';
  Archive := AppDir + '\src.7z';
  if (not FileExists(SevenZip)) or (not FileExists(Archive)) then
  begin
    MsgBox('安装包缺少解压组件，安装中止。' + #13#10 +
      'The setup is missing its extraction component. Aborting.',
      mbError, MB_OK);
    Abort;
  end;
  Params := 'x "' + Archive + '" -o"' + AppDir + '" -y';
  if not Exec(SevenZip, Params, AppDir, SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    MsgBox('无法运行解压器，安装中止。' + #13#10 +
      'Could not start the extractor. Aborting.', mbError, MB_OK);
    Abort;
  end;
  if ResultCode <> 0 then
  begin
    MsgBox('解压失败（code=' + IntToStr(ResultCode) + '），安装中止。' + #13#10 +
      'Extraction failed (code=' + IntToStr(ResultCode) + '). Aborting.', mbError, MB_OK);
    Abort;
  end;
  DeleteFile(Archive);
  Log('[extract] src.7z extracted and removed');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  DataDir: String;
begin
  if CurStep = ssPostInstall then
  begin
    ExtractSrc;
    DataDir := NormalizeDir(DataDirEdit.Text);
    if DataDir = GetDefaultDataDir then
      WriteLauncherConfig('')
    else
      WriteLauncherConfig(DataDir);
    WriteLocalePreference(DataDir);
    CreateShortcuts;
    SetAutoStart(AutoStartCheck.Checked);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDir, LogPath, Prefix: String;
  I: Integer;
  L: TStringList;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    AppDir := ExpandConstant('{app}');
    // Delete only the shortcuts THIS install actually created (recorded in
    // install-log.txt by CreateShortcut). A setup test run in another
    // directory must never touch the real desktop/start-menu shortcuts.
    LogPath := AppDir + '\install-log.txt';
    Prefix := '[shortcut] created: ';
    if FileExists(LogPath) then
    begin
      L := TStringList.Create;
      try
        L.LoadFromFile(LogPath);
        for I := 0 to L.Count - 1 do
          if Pos(Prefix, L[I]) = 1 then
            DeleteFile(Copy(L[I], Length(Prefix) + 1, Length(L[I])));
      finally
        L.Free;
      end;
    end;
    DeleteFile(AppDir + '\apps\desktop-shell\launcher-config.json');
    DeleteFile(AppDir + '\install-log.txt');
    RegDeleteValue(HKCU, RunKey, '{#MyAppName}');
  end;
end;
