$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$backendDir = Join-Path $projectRoot "backend"
$venvPython = Join-Path $backendDir ".venv\Scripts\python.exe"
$databaseFile = Join-Path $backendDir "yks.db"
$releaseExe = Join-Path $projectRoot "frontend\build\windows\x64\runner\Release\yks_tercih_robotu.exe"

Write-Host "2026 YKS Tercih Robotu kurulum / güncelleme" -ForegroundColor Cyan

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python 3.11 veya daha yeni bir sürüm PATH üzerinde bulunamadı."
}

# Çalışan API'yi yalnızca güncelleme sırasında kapatır; öğrenci verilerine dokunmaz.
$listener = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort 8000 `
    -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    & (Join-Path $projectRoot "stop_yks.ps1")
}

if (-not (Test-Path -LiteralPath $venvPython)) {
    python -m venv (Join-Path $backendDir ".venv")
}
& $venvPython -m pip install --disable-pip-version-check -r (Join-Path $backendDir "requirements.txt")

$envFile = Join-Path $backendDir ".env"
if (-not (Test-Path -LiteralPath $envFile)) {
    $secret = [guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
    $databasePath = $databaseFile.Replace("\", "/")
    @(
        "DATABASE_URL=sqlite:///$databasePath"
        "SECRET_KEY=$secret"
        "ACCESS_TOKEN_MINUTES=10080"
        "UPDATE_MANIFEST_URL=https://github.com/umudunatesi/yks-tercih-robotu-guncellemeler/releases/latest/download/latest.json"
    ) | Set-Content -LiteralPath $envFile -Encoding UTF8
}

if (Test-Path -LiteralPath $databaseFile) {
    & $venvPython (Join-Path $projectRoot "scripts\backup_database.py") `
        --database-url "sqlite:///$($databaseFile.Replace('\', '/'))" `
        --output-dir (Join-Path $projectRoot "backups") --keep 10
}

Push-Location $backendDir
try {
    & $venvPython -m alembic upgrade head
} finally {
    Pop-Location
}

$programCount = & $venvPython -c "import sqlite3,sys; db=sqlite3.connect(sys.argv[1]); print(db.execute('SELECT COUNT(*) FROM programs').fetchone()[0])" $databaseFile
if ([int]$programCount -eq 0) {
    $excel = Get-ChildItem -LiteralPath (Join-Path $projectRoot "data") -Filter "*.xlsx" |
        Select-Object -First 1
    if (-not $excel) {
        throw "Kaynak YKS Excel dosyası bulunamadı."
    }
    & $venvPython (Join-Path $projectRoot "scripts\import_yks_excel.py") $excel.FullName
}

& $venvPython (Join-Path $projectRoot "scripts\create_admin.py") --check
if ($LASTEXITCODE -ne 0) {
    Write-Host "İlk yönetici hesabını hazırlayın." -ForegroundColor Yellow
    & $venvPython (Join-Path $projectRoot "scripts\create_admin.py")
}

if (-not (Test-Path -LiteralPath $releaseExe)) {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw "Windows uygulaması bulunamadı ve Flutter kurulu değil."
    }
    Push-Location (Join-Path $projectRoot "frontend")
    try {
        flutter pub get
        flutter build windows --release
    } finally {
        Pop-Location
    }
}

& (Join-Path $projectRoot "verify_windows.ps1")

$launcher = Join-Path $projectRoot "YKS_Tercih_Robotu.vbs"
if (Test-Path -LiteralPath $launcher) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "2026 YKS Tercih Robotu.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\wscript.exe"
    $shortcut.Arguments = "`"$launcher`""
    $shortcut.WorkingDirectory = $projectRoot
    $shortcut.Description = "2026 YKS Tercih Robotu"
    $shortcut.IconLocation = "$releaseExe,0"
    $shortcut.Save()
}

Write-Host "Kurulum / güncelleme tamamlandı." -ForegroundColor Green
Write-Host "Uygulamayı start_yks.bat ile açabilirsiniz."
