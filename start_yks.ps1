$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$backendDir = Join-Path $projectRoot "backend"
$python = Join-Path $backendDir ".venv\Scripts\python.exe"
$releaseDir = Join-Path $projectRoot "frontend\build\windows\x64\runner\Release"
$appExe = Join-Path $releaseDir "yks_tercih_robotu.exe"
$runtimeDir = Join-Path $projectRoot "runtime"
$pidFile = Join-Path $runtimeDir "backend.pid"
$logFile = Join-Path $runtimeDir "backend.log"
$errorLog = Join-Path $runtimeDir "backend-error.log"
$startupLog = Join-Path $runtimeDir "startup.log"

if (-not (Test-Path -LiteralPath $python)) {
    throw "Kurulum bulunamadı. Önce setup_windows.bat dosyasını çalıştırın."
}
if (-not (Test-Path -LiteralPath $appExe)) {
    throw "Windows uygulama buildi bulunamadı: $appExe"
}
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

$backupScript = Join-Path $projectRoot "scripts\backup_database.py"
$databasePath = (Join-Path $backendDir "yks.db").Replace("\", "/")
try {
    & $python $backupScript --database-url "sqlite:///$databasePath" --output-dir (Join-Path $projectRoot "backups") --keep 10 |
        Add-Content -LiteralPath $startupLog -Encoding UTF8
} catch {
    "Otomatik yedekleme uyarısı: $($_.Exception.Message)" |
        Add-Content -LiteralPath $startupLog -Encoding UTF8
}

$healthy = $false
try {
    $response = Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 2
    $healthy = $response.status -eq "ok"
} catch {}

if (-not $healthy) {
    $process = Start-Process -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000") `
        -WorkingDirectory $backendDir -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $logFile -RedirectStandardError $errorLog
    $process.Id | Set-Content -LiteralPath $pidFile -Encoding ASCII
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 500
        try {
            $response = Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 2
            if ($response.status -eq "ok") { $healthy = $true; break }
        } catch {}
    }
}
if (-not $healthy) {
    throw "Backend başlatılamadı. Ayrıntı: $errorLog"
}
$listener = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort 8000 `
    -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $listener) {
    throw "Backend saglikli ancak 8000 portu islemi bulunamadi."
}
$listener.OwningProcess | Set-Content -LiteralPath $pidFile -Encoding ASCII

$runningApp = Get-Process yks_tercih_robotu -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $appExe } |
    Select-Object -First 1
if ($runningApp) {
    Write-Host "Uygulama zaten açık (PID: $($runningApp.Id))." -ForegroundColor Yellow
} else {
    Start-Process -FilePath $appExe -WorkingDirectory $releaseDir
}
