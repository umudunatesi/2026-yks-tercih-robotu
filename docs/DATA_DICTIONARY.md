# Veri Sözlüğü

Kaynak: `2026 YKS TERCİH ROBOTU 29 Temmuz.xlsx`. Asıl başlıklar 2. satırda, veriler 3. satırda başlar.

## Doğrulanan kaynak

| Sayfa | Düzey | Sütun | Kayıt |
|---|---|---:|---:|
| tablo3 | Ön lisans | 35 (A–AI) | 9.254 |
| tablo4 | Lisans | 48 (A–AV) | 12.239 |
| Toplam |  |  | 21.493 |

## Temel alanlar

| Veritabanı alanı | Kaynak | Tür | Kural |
|---|---|---|---|
| program_code | B / KOD-KODU | metin | Excel sayısı olsa da ondalıksız metne çevrilir |
| level | çalışma sayfası | metin | `on_lisans` veya `lisans` |
| university_type | D / C | metin | boşluk ve satır sonları temizlenir |
| region | tablo4 D | metin | yalnız lisans |
| city | E | metin | Türkçe karakter korunur |
| university | G | metin | aranabilir, indeksli |
| faculty | H | metin | `FAKÜLTE/YO/MYO` başlık farkları tolere edilir |
| program | I | metin | aranabilir, indeksli |
| score_type | O | metin | TYT/SAY/EA/SÖZ/DİL |
| quota_2026 | P | tamsayı/null | `--` ve `----` null |
| min_score_2025 | Q | ondalık/null | durum metni sayıya çevrilmez |
| min_rank_2025 | S | tamsayı/null | küçük sayı daha iyi |
| rank_status_2025 | S | metin/null | Yeni, Dolmadı, Yer.Olmadı korunur |
| history | AB:AI / AO:AV | yıllık kayıt | 2018–2025, sayı ve durum ayrı tutulur |

`tablo4` ayrıca bölge, baraj, ücret, MEB bursu, akademik kadro, TUS, DUS, AB AYP ve KPSS alanlarını taşır.
