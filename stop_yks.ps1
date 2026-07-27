$ErrorActionPreference = "Stop"
$pidFile = Join-Path $PSScriptRoot "runtime\backend.pid"
if (-not (Test-Path -LiteralPath $pidFile)) {
    Write-Host "Kayıtlı backend işlemi bulunamadı."
    exit 0
}
$backendPid = [int](Get-Content -LiteralPath $pidFile -Raw)
$process = Get-Process -Id $backendPid -ErrorAction SilentlyContinue
if ($process) {
    $listener = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort 8000 `
        -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.OwningProcess -eq $backendPid }
    if ($listener) {
        Stop-Process -Id $backendPid
        Write-Host "Backend durduruldu."
    } else {
        Write-Warning "PID dosyasindaki islem 8000 portundaki backend degil; durdurulmadi."
    }
}
Remove-Item -LiteralPath $pidFile -Force
