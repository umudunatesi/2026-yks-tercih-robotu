$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$backendDir = Join-Path $projectRoot "backend"
$python = Join-Path $backendDir ".venv\Scripts\python.exe"
$appExe = Join-Path $projectRoot "frontend\build\windows\x64\runner\Release\yks_tercih_robotu.exe"
$database = Join-Path $backendDir "yks.db"

foreach ($required in @($python, $appExe, $database)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Eksik kurulum dosyasi: $required"
    }
}

$checkCode = @"
import sqlite3
import sys
db = sqlite3.connect(sys.argv[1])
integrity = db.execute('PRAGMA integrity_check').fetchone()[0]
programs = db.execute('SELECT COUNT(*) FROM programs').fetchone()[0]
students = db.execute('SELECT COUNT(*) FROM students').fetchone()[0]
db.close()
print(f'{integrity}|{programs}|{students}')
"@
$result = & $python -c $checkCode $database
$parts = $result.Trim().Split("|")
if ($parts[0] -ne "ok") { throw "Veritabani butunluk hatasi: $($parts[0])" }
if ([int]$parts[1] -lt 21482) { throw "Program sayisi beklenenden az: $($parts[1])" }

Write-Host "Kurulum dogrulandi." -ForegroundColor Green
Write-Host "Program: $($parts[1]) | Ogrenci: $($parts[2])"
