$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$python = Join-Path $projectRoot "backend\.venv\Scripts\python.exe"
$sourceDatabase = Join-Path $projectRoot "backend\yks.db"
$workDir = Join-Path $projectRoot "work\acceptance"
$testDatabase = Join-Path $workDir "acceptance.db"

if (-not (Test-Path -LiteralPath $python)) {
    throw "Kurulum bulunamadı. Önce setup_windows.bat çalıştırılmalıdır."
}
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Copy-Item -LiteralPath $sourceDatabase -Destination $testDatabase -Force

$env:DATABASE_URL = "sqlite:///$($testDatabase.Replace('\', '/'))"
$env:SECRET_KEY = "acceptance-test-only-secret"
$testCode = @'
import sqlite3
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.main import app
from app.core.database import SessionLocal
from app.core.security import create_access_token, hash_password
from app.models.entities import Program, User

with SessionLocal() as db:
    user = db.scalar(select(User).where(User.is_active.is_(True)).order_by(User.id))
    if not user:
        user = User(
            email="acceptance@example.test",
            full_name="Kabul Testi",
            password_hash=hash_password("Acceptance-Only-123!"),
            role="admin",
            is_active=True,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    token = create_access_token(user)
    programs = db.scalars(
        select(Program).where(
            Program.score_type.in_(["SAY", "EA", "SÖZ", "DİL"]),
            Program.min_rank_2025.is_not(None),
        ).limit(4)
    ).all()
    assert len(programs) == 4, "Test programları bulunamadı"

client = TestClient(app)
headers = {"Authorization": f"Bearer {token}"}

assert client.get("/health").json() == {"status": "ok"}
assert client.get("/api/dashboard").status_code == 401
assert client.get("/api/dashboard", headers=headers).status_code == 200

student_response = client.post(
    "/api/students-with-results",
    headers=headers,
    json={
        "first_name": "Kabul",
        "last_name": "Testi",
        "school": "Test Okulu",
        "consent_given": True,
        "exam_results": [
            {
                "year": 2026,
                "score_type": score_type,
                "score": 410.25,
                "rank": rank,
            }
            for score_type, rank in (
                ("SAY", 45000),
                ("EA", 80000),
                ("S\u00d6Z", 120000),
                ("D\u0130L", 25000),
            )
        ],
    },
)
assert student_response.status_code == 201, student_response.text
student_id = student_response.json()["id"]
saved_results = client.get(
    f"/api/students/{student_id}/exam-results", headers=headers
)
assert saved_results.status_code == 200
assert len(saved_results.json()) == 4

search = client.get(
    "/api/programs",
    headers=headers,
    params={"score_type": "SAY,EA,SÖZ,DİL", "page_size": 10},
)
assert search.status_code == 200 and search.json()["total"] > 0
associate_region = client.get(
    "/api/programs",
    headers=headers,
    params={"level": "on_lisans", "regions": "MARMARA", "page_size": 10},
)
assert associate_region.status_code == 200
assert associate_region.json()["total"] > 0, "Ön lisans bölge filtresi sonuç vermedi"
lowercase_search = client.get(
    "/api/programs",
    headers=headers,
    params={"q": "istanbul", "page_size": 10},
).json()["total"]
uppercase_search = client.get(
    "/api/programs",
    headers=headers,
    params={"q": "\u0130STANBUL", "page_size": 10},
).json()["total"]
assert lowercase_search == uppercase_search > 0
lowercase_university = client.get(
    "/api/programs",
    headers=headers,
    params={"university": "hacettepe", "page_size": 10},
).json()["total"]
uppercase_university = client.get(
    "/api/programs",
    headers=headers,
    params={"university": "HACETTEPE", "page_size": 10},
).json()["total"]
assert lowercase_university == uppercase_university > 0

payload = {
    "student_id": student_id,
    "name": "Uçtan Uca Kabul Testi",
    "score_type": "KARMA",
    "items": [
        {
            "program_id": program.id,
            "position": index,
            "category": "Değerlendirilecek",
        }
        for index, program in enumerate(programs, 1)
    ],
}
created = client.post("/api/preference-lists", headers=headers, json=payload)
assert created.status_code == 201, created.text
list_id = created.json()["id"]

student_search = client.get(
    "/api/students", headers=headers, params={"q": "kabul testi"}
)
assert student_search.status_code == 200
matching_students = [
    item for item in student_search.json() if item["id"] == student_id
]
assert len(matching_students) == 1
assert matching_students[0]["preference_count"] == 1
assert len(matching_students[0]["preference_history"]) == 1
assert matching_students[0]["preference_history"][0]["id"] == list_id
assert matching_students[0]["preference_history"][0]["created_at"]

detail = client.get(f"/api/preference-lists/{list_id}", headers=headers)
assert detail.status_code == 200 and len(detail.json()["items"]) == 4
for item in detail.json()["items"]:
    program_data = item["program_data"]
    assert program_data["program_code"]
    assert "duration" in program_data
    assert "language" in program_data
    assert "fee_status" in program_data
    assert "rank_2025" in program_data
    assert "rank_2024" in program_data
    assert "rank_2023" in program_data
    assert "special_conditions" in program_data
    assert "accreditation" in program_data

pdf = client.get(f"/api/preference-lists/{list_id}/export.pdf", headers=headers)
assert pdf.status_code == 200 and pdf.content.startswith(b"%PDF") and len(pdf.content) > 5000
xlsx = client.get(f"/api/preference-lists/{list_id}/export.xlsx", headers=headers)
assert xlsx.status_code == 200 and xlsx.content.startswith(b"PK") and len(xlsx.content) > 2000

with sqlite3.connect(r"ACCEPTANCE_DATABASE") as database:
    assert database.execute("PRAGMA integrity_check").fetchone()[0] == "ok"

print(
    "KABUL TESTİ BAŞARILI | öğrenci + 4 puan türü + karma tercih + "
    f"PDF {len(pdf.content)} bayt + Excel {len(xlsx.content)} bayt"
)
'@
$testCode = $testCode.Replace(
    "ACCEPTANCE_DATABASE",
    $testDatabase.Replace("\", "\\")
)

Push-Location (Join-Path $projectRoot "backend")
try {
    $testCode | & $python -
    if ($LASTEXITCODE -ne 0) {
        throw "Kabul testi başarısız oldu."
    }
} finally {
    Pop-Location
    Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:SECRET_KEY -ErrorAction SilentlyContinue
}
