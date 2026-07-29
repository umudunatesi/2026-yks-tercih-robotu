from pathlib import Path
from app.core.regions import cities_for_regions, region_for_city
from app.core.text_search import normalize_search
from app.importers.yks_excel import (
    analyze,
    is_kktc_national_type,
    iter_programs,
    numeric_or_status,
    program_code,
)

SOURCE = Path(__file__).parents[3] / "data" / "2026 YKS TERCİH ROBOTU 29 Temmuz.xlsx"

def test_real_counts():
    report = analyze(SOURCE)
    assert report["counts"] == {"tablo3": 9254, "tablo4": 12239}
    assert report["total"] == 21493
    assert not report["duplicate_codes"]


def test_new_official_programs_are_included():
    programs = {item["program_code"]: item for item in iter_programs(SOURCE)}
    assert len(programs) == 21493
    assert programs["300900115"]["program"] == "Bilgisayar Programcılığı"
    assert programs["300900115"]["level"] == "on_lisans"
    assert programs["102270161"]["program"] == "Çeviribilimi"
    assert programs["102270161"]["extra"]["kktc_national_only"] is True
    assert programs["105590149"]["fee_status"] == "%50 İndirimli"
    assert programs["105590149"]["language"] == "İngilizce"
    assert programs["301410036"]["threshold_rank"] == 80_000
    assert "301410037" not in programs

def test_codes_are_text():
    assert program_code(105590209) == "105590209"

def test_kktc_national_type_is_distinct_from_regular_kktc_programs():
    assert is_kktc_national_type("KKTC U.")
    assert not is_kktc_national_type("KKTC")
    assert not is_kktc_national_type("DEVLET KKTC")
    assert not is_kktc_national_type("KKTC UOLP")

def test_statuses_are_not_numbers():
    for value in ("Yeni", "Dolmadı", "Yer.Olmadı"):
        number, status = numeric_or_status(value)
        assert number is None and status == value
    for value in ("--", "----"):
        assert numeric_or_status(value) == (None, None)


def test_regions_are_inferred_for_associate_degree_cities():
    assert region_for_city("İSTANBUL") == "MARMARA"
    assert region_for_city("ANKARA") == "İÇ ANADOLU"
    assert region_for_city("LEFKOŞA") == "KKTC"
    assert {"İSTANBUL", "BURSA"} <= cities_for_regions(["MARMARA"])


def test_turkish_search_normalization_is_case_insensitive():
    assert normalize_search("İSTANBUL") == normalize_search("istanbul")
    assert normalize_search("ISPARTA") == normalize_search("ısparta")
    assert normalize_search("SÖZEL ÖĞRETMENLİK") == "sozel ogretmenlik"
