import json
import re
from functools import lru_cache
from pathlib import Path


DATA_FILE = Path(__file__).parents[1] / "data" / "special_conditions_2026.json"


@lru_cache(maxsize=1)
def condition_catalog() -> dict[str, str]:
    with DATA_FILE.open(encoding="utf-8") as stream:
        return json.load(stream)


def condition_codes(value: str | None) -> list[str]:
    if not value:
        return []
    return list(dict.fromkeys(re.findall(r"\d+", value)))


def condition_details(value: str | None) -> list[dict[str, str]]:
    catalog = condition_catalog()
    return [
        {"code": code, "description": catalog[code]}
        for code in condition_codes(value)
        if code in catalog
    ]
