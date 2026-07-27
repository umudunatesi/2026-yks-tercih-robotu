REGION_CITIES: dict[str, set[str]] = {
    "MARMARA": {
        "BALIKESİR", "BİLECİK", "BURSA", "ÇANAKKALE", "EDİRNE", "GEBZE",
        "İSTANBUL", "KIRKLARELİ", "KOCAELİ", "SAKARYA", "TEKİRDAĞ", "YALOVA",
    },
    "EGE": {
        "AFYON", "AFYONKARAHİSAR", "AYDIN", "DENİZLİ", "İZMİR", "KÜTAHYA",
        "MANİSA", "MUĞLA", "UŞAK",
    },
    "AKDENİZ": {
        "ADANA", "ANTALYA", "BURDUR", "HATAY", "ISPARTA", "KAHRAMANMARAŞ",
        "MERSİN", "OSMANİYE",
    },
    "İÇ ANADOLU": {
        "AKSARAY", "ANKARA", "ÇANKIRI", "ESKİŞEHİR", "KARAMAN", "KAYSERİ",
        "KIRIKKALE", "KIRŞEHİR", "KONYA", "NEVŞEHİR", "NİĞDE", "SİVAS",
        "YOZGAT",
    },
    "KARADENİZ": {
        "AMASYA", "ARTVİN", "BARTIN", "BAYBURT", "BOLU", "ÇORUM", "DÜZCE",
        "GİRESUN", "GÜMÜŞHANE", "KARABÜK", "KASTAMONU", "ORDU", "RİZE",
        "SAMSUN", "SİNOP", "TOKAT", "TRABZON", "ZONGULDAK",
    },
    "DOĞU ANADOLU": {
        "AĞRI", "ARDAHAN", "BİNGÖL", "BİTLİS", "ELAZIĞ", "ERZİNCAN",
        "ERZURUM", "HAKKARİ", "IĞDIR", "KARS", "MALATYA", "MUŞ", "TUNCELİ",
        "VAN",
    },
    "GÜNEY DOĞU": {
        "ADIYAMAN", "BATMAN", "DİYARBAKIR", "GAZİANTEP", "KİLİS", "MARDİN",
        "SİİRT", "ŞANLIURFA", "ŞIRNAK",
    },
    "KKTC": {"GAZİMAĞUSA", "GİRNE", "GÜZELYURT", "LEFKE", "LEFKOŞA"},
    "YURT DIŞI": {"TÜRKİSTAN KAZAKİSTAN"},
}


def region_for_city(city: str | None) -> str | None:
    if not city:
        return None
    normalized = city.strip().upper()
    for region, cities in REGION_CITIES.items():
        if normalized in cities:
            return region
    return None


def cities_for_regions(regions: list[str]) -> set[str]:
    return {
        city
        for region in regions
        for city in REGION_CITIES.get(region.strip().upper(), set())
    }
