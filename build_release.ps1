$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$version = "1.3.4"
$outputRoot = Join-Path (Split-Path $projectRoot -Parent) "outputs\releases"
$packageName = "2026-YKS-Tercih-Robotu-$version"
$stage = Join-Path $outputRoot $packageName
$archive = Join-Path $outputRoot "$packageName.zip"
$python = Join-Path $projectRoot "backend\.venv\Scripts\python.exe"
$releaseApp = Join-Path $projectRoot "frontend\build\windows\x64\runner\Release"
$backendRuntime = Join-Path $projectRoot "backend\dist\yks_backend"

if (-not (Test-Path -LiteralPath $python)) {
    throw "Python ortamı bulunamadı."
}
if (-not (Test-Path -LiteralPath (Join-Path $releaseApp "yks_tercih_robotu.exe"))) {
    throw "Windows Release uygulaması bulunamadı."
}
if (-not (Test-Path -LiteralPath (Join-Path $backendRuntime "yks_backend.exe"))) {
    throw "Derlenmiş backend bulunamadı."
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$resolvedOutput = (Resolve-Path $outputRoot).Path
if ($stage -notlike "$resolvedOutput\*") {
    throw "Geçersiz paket hedefi: $stage"
}
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}

foreach ($directory in @(
    "backend", "frontend", "data", "docs", "scripts", "backups", "runtime"
)) {
    New-Item -ItemType Directory -Force -Path (Join-Path $stage $directory) |
        Out-Null
}
Copy-Item -LiteralPath (Join-Path $projectRoot "backend\app") `
    -Destination (Join-Path $stage "backend\app") -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot "backend\alembic") `
    -Destination (Join-Path $stage "backend\alembic") -Recurse
Copy-Item -LiteralPath $backendRuntime `
    -Destination (Join-Path $stage "backend\bin") -Recurse
Copy-Item -Path (Join-Path $projectRoot "scripts\*") `
    -Destination (Join-Path $stage "scripts") -Recurse
Copy-Item -Path (Join-Path $projectRoot "docs\*") `
    -Destination (Join-Path $stage "docs") -Recurse
Copy-Item -Path (Join-Path $projectRoot "data\*") `
    -Destination (Join-Path $stage "data") -Recurse
New-Item -ItemType Directory -Force -Path `
    (Join-Path $stage "frontend\build\windows\x64\runner") | Out-Null
Copy-Item -LiteralPath $releaseApp -Destination `
    (Join-Path $stage "frontend\build\windows\x64\runner\Release") -Recurse

foreach ($file in @(
    "backend\alembic.ini",
    "backend\requirements.txt",
    "backend\pyproject.toml",
    ".env.example",
    "README.md",
    "KULLANIMA_BASLA.txt",
    "SURUM_NOTLARI_1.3.4.txt",
    "setup_windows.bat",
    "setup_windows.ps1",
    "start_yks.bat",
    "start_yks.ps1",
    "stop_yks.bat",
    "stop_yks.ps1",
    "verify_windows.bat",
    "verify_windows.ps1",
    "smoke_test.bat",
    "smoke_test.ps1",
    "acceptance_test.bat",
    "acceptance_test.ps1",
    "support_report.bat",
    "support_report.ps1",
    "restore_latest_backup.bat",
    "restore_latest_backup.ps1",
    "YKS_Tercih_Robotu.vbs"
)) {
    $source = Join-Path $projectRoot $file
    $destination = Join-Path $stage $file
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) |
        Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
}

& $python (Join-Path $projectRoot "scripts\prepare_release_database.py") `
    (Join-Path $projectRoot "backend\yks.db") `
    (Join-Path $stage "backend\yks.db")
if ($LASTEXITCODE -ne 0) {
    throw "Temiz dağıtım veritabanı hazırlanamadı."
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stage,
    $archive,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
"$hash  $packageName.zip" | Set-Content `
    -LiteralPath "$archive.sha256.txt" -Encoding ASCII
Write-Host "Dağıtım paketi hazır: $archive" -ForegroundColor Green
Write-Host "SHA256: $hash"
