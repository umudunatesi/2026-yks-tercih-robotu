from statistics import median

DEFAULT_THRESHOLDS = {"high_target": -0.20, "target": -0.05, "balanced": 0.15}

def classify(student_rank: int, program_rank: int | None, status: str | None = None, history=None, thresholds=None):
    if status == "Yeni": return {"category": "Yeni program", "explanation": "Program yenidir ve yeterli geçmiş veri bulunmamaktadır."}
    if status in {"Dolmadı", "Yer.Olmadı"}: return {"category": "Geçen yıl dolmadı", "explanation": "Program 2025 yılında kontenjanını doldurmamıştır."}
    if not program_rank or not student_rank: return {"category": "Verisi yetersiz", "explanation": "Sayısal başarı sırası verisi yeterli değildir."}
    t = thresholds or DEFAULT_THRESHOLDS
    relative = (program_rank - student_rank) / student_rank
    category = "Yüksek hedef" if relative < t["high_target"] else "Hedef aralığı" if relative < t["target"] else "Dengeli" if relative < t["balanced"] else "Daha güvenli"
    percent = abs(relative) * 100
    direction = "daha iyi" if program_rank < student_rank else "daha geride"
    values = [x for x in (history or []) if isinstance(x, (int, float))]
    return {"category": category, "relative_difference": relative,
            "trend_median": median(values[-3:]) if values else None,
            "explanation": f"Programın 2025 sıralaması öğrencinin sıralamasından yaklaşık %{percent:.1f} {direction}. Kesin yerleşme garantisi vermez."}
