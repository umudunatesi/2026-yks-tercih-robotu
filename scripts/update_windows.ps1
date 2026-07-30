param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][string]$ManifestUrl,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion
)

$ErrorActionPreference = "Stop"
$install = [System.IO.Path]::GetFullPath($InstallRoot)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("yks-update-" + [guid]::NewGuid())
$downloadPath = Join-Path $tempRoot "update.zip"
$extractPath = Join-Path $tempRoot "package"
$rollbackPath = Join-Path $tempRoot "rollback"
$logDir = Join-Path $install "runtime"
$logPath = Join-Path $logDir "update.log"

function Write-UpdateLog([string]$Message) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" |
        Add-Content -LiteralPath $logPath -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $install)) {
        throw "Kurulum dizini bulunamadı: $install"
    }
    New-Item -ItemType Directory -Force -Path $tempRoot, $extractPath, $rollbackPath |
        Out-Null
    Write-UpdateLog "Güncelleme başlatıldı. Hedef sürüm: $ExpectedVersion"

    $manifest = Invoke-RestMethod -Uri $ManifestUrl -TimeoutSec 20
    if ([string]$manifest.version -ne $ExpectedVersion) {
        throw "Manifest sürümü değişti. Beklenen: $ExpectedVersion, gelen: $($manifest.version)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.download_url)) {
        throw "Manifest paket adresi içermiyor."
    }
    $expectedHash = ([string]$manifest.sha256).Trim().ToUpperInvariant()
    if ($expectedHash -notmatch '^[A-F0-9]{64}$') {
        throw "Manifest SHA-256 değeri geçersiz."
    }

    Invoke-WebRequest -Uri ([string]$manifest.download_url) `
        -OutFile $downloadPath -TimeoutSec 300
    $actualHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        throw "Paket doğrulaması başarısız. Dosya değiştirilmiş veya eksik olabilir."
    }
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $extractPath -Force
    foreach ($required in @(
        "frontend\build\windows\x64\runner\Release\yks_tercih_robotu.exe",
        "backend\app",
        "start_yks.ps1"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $extractPath $required))) {
            throw "Güncelleme paketi eksik: $required"
        }
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $install "backups") |
        Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $database = Join-Path $install "backend\yks.db"
    if (Test-Path -LiteralPath $database) {
        Copy-Item -LiteralPath $database `
            -Destination (Join-Path $install "backups\yks-before-update-$stamp.db") -Force
    }
    foreach ($relative in @("backend\app", "frontend\build\windows\x64\runner\Release", "scripts")) {
        $source = Join-Path $install $relative
        if (Test-Path -LiteralPath $source) {
            $target = Join-Path $rollbackPath $relative
            New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) |
                Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
        }
    }

    Start-Sleep -Seconds 3
    $appExe = Join-Path $install "frontend\build\windows\x64\runner\Release\yks_tercih_robotu.exe"
    Get-CimInstance Win32_Process |
        Where-Object { $_.ExecutablePath -eq $appExe } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $listener = Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort 8000 `
        -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($listener) {
        Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2

    # Dağıtım paketindeki boş veritabanı hiçbir koşulda kullanıcı verisini ezmez.
    $packagedDatabase = Join-Path $extractPath "backend\yks.db"
    if (Test-Path -LiteralPath $packagedDatabase) {
        $catalogDatabase = Join-Path $extractPath "backend\catalog-update.db"
        if (-not (Test-Path -LiteralPath $catalogDatabase)) {
            Copy-Item -LiteralPath $packagedDatabase `
                -Destination $catalogDatabase -Force
        }
        Remove-Item -LiteralPath $packagedDatabase -Force
    }
    Copy-Item -Path (Join-Path $extractPath "*") -Destination $install `
        -Recurse -Force
    Write-UpdateLog "Dosyalar $ExpectedVersion sürümüne güncellendi."
} catch {
    Write-UpdateLog "Güncelleme hatası: $($_.Exception.Message)"
    try {
        foreach ($relative in @("backend\app", "frontend\build\windows\x64\runner\Release", "scripts")) {
            $backup = Join-Path $rollbackPath $relative
            if (Test-Path -LiteralPath $backup) {
                Copy-Item -LiteralPath $backup -Destination (Split-Path (Join-Path $install $relative) -Parent) `
                    -Recurse -Force
            }
        }
        Write-UpdateLog "Önceki uygulama dosyaları geri yüklendi."
    } catch {
        Write-UpdateLog "Geri yükleme hatası: $($_.Exception.Message)"
    }
} finally {
    try {
        $startScript = Join-Path $install "start_yks.ps1"
        if (Test-Path -LiteralPath $startScript) {
            Start-Process -FilePath "powershell.exe" -WindowStyle Hidden `
                -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$startScript`"")
        }
    } catch {
        Write-UpdateLog "Uygulama yeniden başlatılamadı: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
