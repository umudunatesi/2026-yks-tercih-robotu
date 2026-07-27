from types import SimpleNamespace
from app.core.security import hash_password, verify_password
from app.services.exports import (
    format_kpss, preference_csv, preference_pdf, preference_xlsx,
)

def test_password_hashing():
    hashed = hash_password("GucluSifre123")
    assert hashed != "GucluSifre123"
    assert verify_password("GucluSifre123", hashed)
    assert not verify_password("yanlis", hashed)

def test_csv_formula_injection():
    program = SimpleNamespace(program_code="123", university="=HYPERLINK('x')", faculty="F", program="P",
                              city="İstanbul", score_type="SAY", min_rank_2025=10)
    item = SimpleNamespace(position=1, program=program, category="Dengeli", note="+cmd")
    data = preference_csv([item]).decode("utf-8-sig")
    assert "'=HYPERLINK" in data and "'+cmd" in data

def test_xlsx_is_valid_zip():
    program = SimpleNamespace(program_code="123", university="Ü", faculty="F", program="P",
                              city="İstanbul", score_type="SAY", min_rank_2025=10)
    item = SimpleNamespace(position=1, program=program, category="Dengeli", note="Not")
    assert preference_xlsx([item]).startswith(b"PK")

def test_pdf_is_generated_with_turkish_text():
    program = SimpleNamespace(program_code="123", university="İstanbul Üniversitesi", faculty="Mühendislik",
                              program="Bilgisayar Mühendisliği", city="İstanbul", score_type="SAY",
                              min_rank_2025=10, extra={"kpss": "88.814177"})
    item = SimpleNamespace(position=1, program=program, category="Dengeli", note="Türkçe açıklama")
    pref = SimpleNamespace(id=1, version=1)
    student = SimpleNamespace(first_name="Çağrı", last_name="Öğüt", school="Örnek Lisesi")
    pdf = preference_pdf(pref, student, [item])
    assert pdf.startswith(b"%PDF") and len(pdf) > 10_000


def test_kpss_display_uses_three_decimal_places():
    assert format_kpss("88.814177") == "88.814"
    assert format_kpss(None) == "—"
