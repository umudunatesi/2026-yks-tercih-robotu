from app.services.special_conditions import condition_codes, condition_details


def test_condition_codes_are_unique_and_keep_source_order():
    assert condition_codes("18, 21, 18, 22") == ["18", "21", "22"]


def test_condition_details_match_known_guide_entry():
    details = condition_details("14, 9999")
    assert [item["code"] for item in details] == ["14"]
    assert "Arapça" in details[0]["description"]


def test_first_and_second_condition_sections_are_both_available():
    details = condition_details("144, 155")
    assert [item["code"] for item in details] == ["144", "155"]
    assert "Mühendislik programlarına" in details[0]["description"]
    assert "Tıp programlarına" in details[1]["description"]
