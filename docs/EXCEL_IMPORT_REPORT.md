# Excel İçe Aktarma Raporu

- Dosya: `2026 YKS TERCİH ROBOTU 29 Temmuz.xlsx`
- Analiz tarihi: 29 Temmuz 2026
- `tablo3`: 9.254 kayıt, 35 sütun
- `tablo4`: 12.239 kayıt, 48 sütun
- Toplam: 21.493 kayıt
- Beklenen sayılarla sonuç: eşleşti
- Program kodu yaklaşımı: kaynakta sayısal görünen kodlar kayıpsız metne dönüştürülür
- Boş satırlar: tüm hücreleri boş satırlar atlanır
- Durumlar: `Yeni`, `Dolmadı`, `Yer.Olmadı` ayrı durum; `--` ve `----` null
- Upsert anahtarı: veri yılı + program kodu
- Geri dönüş: her yükleme `data_imports` sürümü olarak kaydedilir; önceki sürüm silinmez

Import, kayıt sayısı veya program kodu benzersizliği doğrulaması başarısızsa veritabanını değiştirmeden durur.
