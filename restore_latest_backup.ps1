$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$python = Join-Path $projectRoot "backend\.venv\Scripts\python.exe"
$database = Join-Path $projectRoot "backend\yks.db"
$latest = Get-ChildItem -LiteralPath (Join-Path $projectRoot "backups") `
    -Filter "yks-*.db" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latest) {
    throw "Geri yüklenecek yedek bulunamadı."
}
Write-Host "Geri yüklenecek yedek: $($latest.Name)" -ForegroundColor Yellow
$confirmation = Read-Host "Mevcut veritabanı değiştirilecek. Devam etmek için EVET yazın"
if ($confirmation -cne "EVET") {
    Write-Host "İşlem iptal edildi."
    exit 0
}

& (Join-Path $projectRoot "stop_yks.ps1")
& $python (Join-Path $projectRoot "scripts\restore_database.py") `
    $latest.FullName `
    --database-url "sqlite:///$($database.Replace('\', '/'))" --yes
& (Join-Path $projectRoot "verify_windows.ps1")
& (Join-Path $projectRoot "start_yks.ps1")
Write-Host "Son yedek geri yüklendi ve uygulama açıldı." -ForegroundColor Green
