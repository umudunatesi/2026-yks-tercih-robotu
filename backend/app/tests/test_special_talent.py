from app.services.special_talent import (
    filter_special_talent_programs,
    special_talent_data,
    special_talent_filter_options,
)


def test_special_talent_dataset_is_complete_and_unique():
    items = special_talent_data()["items"]
    assert len(items) == 1246
    assert len({item["program_code"] for item in items}) == len(items)
    assert all(item["university"] and item["unit"] for item in items)
    assert all(item["quota"] is not None for item in items)


def test_special_talent_types_and_filters():
    options = special_talent_filter_options()
    assert options["institution_types"] == ["Devlet", "KKTC", "Vakıf"]
    assert len(filter_special_talent_programs(institution_type="Devlet")) == 934
    assert len(filter_special_talent_programs(institution_type="Vakıf")) == 247
    assert len(filter_special_talent_programs(institution_type="KKTC")) == 65


def test_special_talent_search_is_turkish_case_insensitive():
    upper = filter_special_talent_programs(query="MÜZİK")
    lower = filter_special_talent_programs(query="müzik")
    assert upper
    assert [item["program_code"] for item in upper] == [
        item["program_code"] for item in lower
    ]


def test_special_talent_conditions_are_explained():
    items = special_talent_data()["items"]
    assert all(
        len(item["special_condition_codes"])
        == len(item["special_condition_details"])
        for item in items
    )


def test_condition_five_and_combined_conditions_are_preserved():
    items = {
        item["program_code"]: item for item in special_talent_data()["items"]
    }
    assert items["101090541"]["special_condition_codes"] == ["5"]
    assert items["101090601"]["special_condition_codes"] == ["1", "5"]
    detail = items["101090541"]["special_condition_details"][0]
    assert detail["code"] == "5"
    assert "engelli adaylara ilişkin genel açıklama" in detail["description"]
