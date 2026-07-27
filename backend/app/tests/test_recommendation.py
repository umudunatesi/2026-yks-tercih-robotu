from app.services.recommendation import classify

def test_smaller_rank_is_better_and_riskier():
    assert classify(50_000, 30_000)["category"] == "Yüksek hedef"
    assert classify(50_000, 80_000)["category"] == "Daha güvenli"

def test_special_statuses():
    assert classify(50_000, None, "Yeni")["category"] == "Yeni program"
    assert classify(50_000, None, "Dolmadı")["category"] == "Geçen yıl dolmadı"
