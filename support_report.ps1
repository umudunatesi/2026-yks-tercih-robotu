$ErrorActionPreference = "Continue"
$projectRoot = $PSScriptRoot
$runtimeDir = Join-Path $projectRoot "runtime"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDir = Join-Path $projectRoot "support-reports\$stamp"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$summary = @(
    "2026 YKS Tercih Robotu Destek Raporu"
    "Tarih: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Windows: $([Environment]::OSVersion.VersionString)"
    "PowerShell: $($PSVersionTable.PSVersion)"
)

try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 3
    $summary += "Backend: $($health.status)"
} catch {
    $summary += "Backend: erişilemiyor"
}

$listener = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort 8000 `
    -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $summary += "Backend PID: $($listener.OwningProcess)"
}

Get-Process yks_tercih_robotu -ErrorAction SilentlyContinue |
    Select-Object Id, StartTime, Path |
    Format-List |
    Out-String |
    Set-Content -LiteralPath (Join-Path $reportDir "application-process.txt") -Encoding UTF8

if (Test-Path -LiteralPath $runtimeDir) {
    Get-ChildItem -LiteralPath $runtimeDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq ".log" } |
        Copy-Item -Destination $reportDir -Force
}

$summary | Set-Content -LiteralPath (Join-Path $reportDir "summary.txt") -Encoding UTF8
$archive = "$reportDir.zip"
Compress-Archive -LiteralPath $reportDir -DestinationPath $archive -Force
Write-Host "Destek raporu hazırlandı:" -ForegroundColor Green
Write-Host $archive
