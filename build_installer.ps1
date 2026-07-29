$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$version = "1.3.5"
$python = Join-Path $projectRoot "backend\.venv\Scripts\python.exe"
$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$outputDir = Join-Path (Split-Path $projectRoot -Parent) "outputs\releases"
$packageDir = Join-Path $outputDir "2026-YKS-Tercih-Robotu-$version"
$installer = Join-Path $outputDir "2026-YKS-Tercih-Robotu-Setup-$version.exe"

if (-not (Test-Path -LiteralPath $python)) {
    throw "Python geliştirme ortamı bulunamadı."
}
if (-not (Test-Path -LiteralPath $iscc)) {
    throw "Inno Setup 6 bulunamadı."
}

Push-Location (Join-Path $projectRoot "backend")
try {
    & $python -m PyInstaller --clean --noconfirm "yks_backend.spec"
    if ($LASTEXITCODE -ne 0) { throw "Backend derlenemedi." }
} finally {
    Pop-Location
}

Push-Location (Join-Path $projectRoot "frontend")
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Flutter uygulaması derlenemedi." }
} finally {
    Pop-Location
}

& (Join-Path $projectRoot "build_release.ps1")
if ($LASTEXITCODE -ne 0) { throw "Dağıtım paketi hazırlanamadı." }

& $iscc `
    "/DAppVersion=$version" `
    "/DPackageDir=$packageDir" `
    "/DOutputDir=$outputDir" `
    (Join-Path $projectRoot "installer\2026-yks-tercih-robotu.iss")
if ($LASTEXITCODE -ne 0) { throw "Windows kurucusu oluşturulamadı." }

$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
"$hash  $(Split-Path $installer -Leaf)" |
    Set-Content -LiteralPath "$installer.sha256.txt" -Encoding ASCII
$archive = Join-Path $outputDir "2026-YKS-Tercih-Robotu-$version.zip"
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$manifest = [ordered]@{
    version = $version
    download_url = "https://github.com/umudunatesi/2026-yks-tercih-robotu/releases/download/v$version/2026-YKS-Tercih-Robotu-$version.zip"
    sha256 = $archiveHash
    release_notes = @(
        "Tek dosyalık Windows kurucusu",
        "Python gerektirmeyen çevrimdışı kurulum",
        "Kurulum sırasında yönetici hesabı oluşturma"
    )
    mandatory = $false
}
$manifest | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $outputDir "latest.json") -Encoding UTF8
Write-Host "Windows kurucusu hazır: $installer" -ForegroundColor Green
Write-Host "SHA256: $hash"
