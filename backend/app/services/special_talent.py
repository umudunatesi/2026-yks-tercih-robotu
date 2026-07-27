import json
from functools import lru_cache
from pathlib import Path

from app.core.text_search import normalize_search


DATA_FILE = (
    Path(__file__).parents[1] / "data" / "special_talent_programs_2026.json"
)


@lru_cache(maxsize=1)
def special_talent_data() -> dict:
    with DATA_FILE.open(encoding="utf-8") as stream:
        return json.load(stream)


def filter_special_talent_programs(
    *,
    query: str | None = None,
    institution_type: str | None = None,
    university: str | None = None,
    accreditation: str | None = None,
    condition_code: str | None = None,
    min_quota: int | None = None,
    max_quota: int | None = None,
    kktc_national_only: bool | None = None,
) -> list[dict]:
    query_key = normalize_search(query)
    university_key = normalize_search(university)
    accreditation_key = normalize_search(accreditation)
    type_key = normalize_search(institution_type)
    results = []
    for item in special_talent_data()["items"]:
        haystack = normalize_search(
            " ".join([
                item.get("program") or "",
                item.get("university") or "",
                item.get("unit") or "",
                item.get("program_code") or "",
            ])
        )
        if query_key and query_key not in haystack:
            continue
        if type_key and normalize_search(item.get("institution_type")) != type_key:
            continue
        if university_key and university_key not in normalize_search(
            item.get("university")
        ):
            continue
        if accreditation_key and accreditation_key not in normalize_search(
            " ".join([
                item.get("program_accreditation") or "",
                item.get("university_accreditation") or "",
            ])
        ):
            continue
        if condition_code and condition_code not in item.get(
            "special_condition_codes", []
        ):
            continue
        quota = item.get("quota")
        if min_quota is not None and (quota is None or quota < min_quota):
            continue
        if max_quota is not None and (quota is None or quota > max_quota):
            continue
        if kktc_national_only is True and not item.get("kktc_national_only"):
            continue
        results.append(item)
    return results


def special_talent_filter_options() -> dict:
    items = special_talent_data()["items"]
    return {
        "institution_types": sorted({
            item["institution_type"] for item in items
            if item.get("institution_type")
        }),
        "universities": sorted({
            item["university"] for item in items if item.get("university")
        }, key=normalize_search),
        "accreditations": sorted({
            value
            for item in items
            for value in (
                item.get("program_accreditation"),
                item.get("university_accreditation"),
            )
            if value
        }, key=normalize_search),
        "condition_codes": sorted(
            special_talent_data()["condition_catalog"],
            key=int,
        ),
    }
