#ifndef AppVersion
  #error AppVersion tanımlanmadı
#endif
#ifndef PackageDir
  #error PackageDir tanımlanmadı
#endif
#ifndef OutputDir
  #error OutputDir tanımlanmadı
#endif

[Setup]
AppId={{D789ED88-7C3F-4A0C-87A4-7E021B1AB831}
AppName=2026 YKS Tercih Robotu
AppVersion={#AppVersion}
AppPublisher=Psikolojik Danışman Uğur Güdük
AppPublisherURL=https://github.com/umudunatesi/2026-yks-tercih-robotu
AppSupportURL=https://github.com/umudunatesi/2026-yks-tercih-robotu/issues
DefaultDirName={localappdata}\Programs\2026 YKS Tercih Robotu
DefaultGroupName=2026 YKS Tercih Robotu
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=2026-YKS-Tercih-Robotu-Setup-{#AppVersion}
SetupIconFile=..\frontend\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\frontend\build\windows\x64\runner\Release\yks_tercih_robotu.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany=Psikolojik Danışman Uğur Güdük
VersionInfoDescription=2026 YKS Tercih Robotu Windows Kurulumu
VersionInfoProductName=2026 YKS Tercih Robotu
VersionInfoProductVersion={#AppVersion}

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; \
  Excludes: "backend\yks.db"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PackageDir}\backend\yks.db"; DestDir: "{app}\seed"; \
  DestName: "yks.db"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\2026 YKS Tercih Robotu"; Filename: "{sys}\wscript.exe"; \
  Parameters: """{app}\YKS_Tercih_Robotu.vbs"""; WorkingDir: "{app}"; \
  IconFilename: "{app}\frontend\build\windows\x64\runner\Release\yks_tercih_robotu.exe"
Name: "{autodesktop}\2026 YKS Tercih Robotu"; Filename: "{sys}\wscript.exe"; \
  Parameters: """{app}\YKS_Tercih_Robotu.vbs"""; WorkingDir: "{app}"; \
  IconFilename: "{app}\frontend\build\windows\x64\runner\Release\yks_tercih_robotu.exe"

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\YKS_Tercih_Robotu.vbs"""; \
  Description: "2026 YKS Tercih Robotu'nu aç"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\stop_yks.ps1"""; \
  Flags: runhidden waituntilterminated; RunOnceId: "StopYksBackend"

[Code]
var
  AdminPage: TInputQueryWizardPage;
  WasFreshInstall: Boolean;

function JsonEscape(Value: String): String;
begin
  StringChangeEx(Value, '\', '\\', True);
  StringChangeEx(Value, '"', '\"', True);
  StringChangeEx(Value, #13#10, '\n', True);
  Result := Value;
end;

function DatabasePath(): String;
begin
  Result := ExpandConstant('{app}\backend\yks.db');
end;

procedure InitializeWizard;
begin
  WasFreshInstall := True;
  AdminPage := CreateInputQueryPage(
    wpSelectDir,
    'İlk yönetici hesabı',
    'Uygulamaya giriş bilgilerinizi belirleyin',
    'Bu bilgiler yalnızca bilgisayarınızdaki yerel veritabanına kaydedilir.'
  );
  AdminPage.Add('Ad soyad:', False);
  AdminPage.Add('E-posta:', False);
  AdminPage.Add('Şifre (en az 10 karakter):', True);
  AdminPage.Add('Şifre tekrar:', True);
  AdminPage.Values[0] := 'Sistem Yöneticisi';
  AdminPage.Values[1] := 'admin@example.local';
  if ExpandConstant('{param:ADMINNAME|}') <> '' then
    AdminPage.Values[0] := ExpandConstant('{param:ADMINNAME|}');
  if ExpandConstant('{param:ADMINEMAIL|}') <> '' then
    AdminPage.Values[1] := ExpandConstant('{param:ADMINEMAIL|}');
  if ExpandConstant('{param:ADMINPASSWORD|}') <> '' then
  begin
    AdminPage.Values[2] := ExpandConstant('{param:ADMINPASSWORD|}');
    AdminPage.Values[3] := ExpandConstant('{param:ADMINPASSWORD|}');
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  if PageID = AdminPage.ID then
  begin
    WasFreshInstall := not FileExists(DatabasePath());
    Result := not WasFreshInstall;
  end
  else
    Result := False;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = AdminPage.ID) and WasFreshInstall then
  begin
    if Trim(AdminPage.Values[0]) = '' then
    begin
      MsgBox('Ad soyad alanı zorunludur.', mbError, MB_OK);
      Result := False;
    end
    else if Pos('@', AdminPage.Values[1]) = 0 then
    begin
      MsgBox('Geçerli bir e-posta adresi girin.', mbError, MB_OK);
      Result := False;
    end
    else if Length(AdminPage.Values[2]) < 10 then
    begin
      MsgBox('Şifre en az 10 karakter olmalıdır.', mbError, MB_OK);
      Result := False;
    end
    else if AdminPage.Values[2] <> AdminPage.Values[3] then
    begin
      MsgBox('Şifreler eşleşmiyor.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\stop_yks.ps1')) then
    Exec(
      'powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -File "' +
        ExpandConstant('{app}\stop_yks.ps1') + '"',
      ExpandConstant('{app}'),
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode
    );
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  AdminJson: String;
  AdminFile: String;
  ResultCode: Integer;
begin
  if CurStep <> ssPostInstall then
    Exit;

  Log('YKS init: dizinler');
  ForceDirectories(ExpandConstant('{app}\backend'));
  ForceDirectories(ExpandConstant('{app}\backups'));
  ForceDirectories(ExpandConstant('{app}\runtime'));

  Log('YKS init: veritabanı');
  if not FileExists(DatabasePath()) then
  begin
    if not FileCopy(ExpandConstant('{app}\seed\yks.db'), DatabasePath(), False) then
      RaiseException('Başlangıç veritabanı hazırlanamadı.');
    WasFreshInstall := True;
  end;

  Log('YKS init: admin kontrolü');
  if WasFreshInstall then
  begin
    Log('YKS init: admin json');
    AdminFile := ExpandConstant('{tmp}\yks-admin.json');
    AdminJson :=
      '{"full_name":"' + JsonEscape(AdminPage.Values[0]) +
      '","email":"' + JsonEscape(AdminPage.Values[1]) +
      '","password":"' + JsonEscape(AdminPage.Values[2]) + '"}';
    SaveStringToFile(AdminFile, AnsiString(AdminJson), False);
    Log('YKS init: admin exe');
    if not Exec(
      ExpandConstant('{app}\backend\bin\yks_backend.exe'),
      '--bootstrap-admin-file "' + AdminFile + '" --database "' +
        DatabasePath() + '"',
      ExpandConstant('{app}\backend'),
      SW_HIDE,
      ewWaitUntilTerminated,
      ResultCode
    ) or (ResultCode <> 0) then
      RaiseException(
        'Yönetici hesabı oluşturulamadı. Hata kodu: ' +
        IntToStr(ResultCode)
      );
  end;
end;
