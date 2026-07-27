$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$python = Join-Path $projectRoot "backend\.venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python)) {
    throw "Kurulum bulunamadı. Önce setup_windows.bat çalıştırılmalıdır."
}

$testCode = @'
import sqlite3
from fastapi.testclient import TestClient
from sqlalchemy import select
from app.main import app
from app.core.database import SessionLocal
from app.core.security import create_access_token
from app.models.entities import User

db_file = "yks.db"
with sqlite3.connect(db_file) as raw:
    integrity = raw.execute("PRAGMA integrity_check").fetchone()[0]
    program_count = raw.execute("SELECT COUNT(*) FROM programs").fetchone()[0]
assert integrity == "ok", integrity
assert program_count >= 21482, program_count

with SessionLocal() as db:
    user = db.scalar(
        select(User).where(User.is_active.is_(True)).order_by(User.id)
    )
    assert user, "Etkin kullanıcı bulunamadı"
    token = create_access_token(user)

headers = {"Authorization": f"Bearer {token}"}
client = TestClient(app)

def check(path, **kwargs):
    response = client.get(path, headers=headers, **kwargs)
    assert response.status_code == 200, f"{path}: {response.status_code}"
    return response

assert client.get("/api/dashboard").status_code == 401
dashboard = check("/api/dashboard").json()
students = check("/api/students").json()
programs = check(
    "/api/programs",
    params={"q": "Hacettepe", "score_type": "SAY,EA", "page_size": 10},
).json()
regions = check(
    "/api/programs",
    params={"regions": "GÜNEY DOĞU,KKTC", "page_size": 10},
).json()
lists = check("/api/preference-lists").json()
check("/api/reports/summary")

pdf_size = 0
if lists:
    list_id = lists[0]["id"]
    detail = check(f"/api/preference-lists/{list_id}").json()
    assert all(item.get("score_type") for item in detail["items"])
    pdf = check(f"/api/preference-lists/{list_id}/export.pdf")
    assert pdf.content.startswith(b"%PDF")
    pdf_size = len(pdf.content)

print("TÜM KONTROLLER BAŞARILI")
print(
    f"Program: {dashboard['programs']} | Öğrenci: {len(students)} | "
    f"Hacettepe SAY/EA: {programs['total']} | Bölge sonucu: {regions['total']} | "
    f"Liste: {len(lists)} | PDF: {pdf_size} bayt"
)
'@

Push-Location (Join-Path $projectRoot "backend")
try {
    $testCode | & $python -
    if ($LASTEXITCODE -ne 0) {
        throw "Duman testi başarısız oldu."
    }
} finally {
    Pop-Location
}
