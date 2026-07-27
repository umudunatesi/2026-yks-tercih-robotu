# 2026 YKS Tercih Robotu

Flutter Web/Windows istemcisi ile FastAPI tabanlı, SQLite geliştirme ve PostgreSQL üretim desteği bulunan Türkçe karar destek uygulaması.

Uygulamada gerçek 21.482 program üzerinde gelişmiş arama, 2018–2025 sıralama grafiği, öğrenci ve görüşme notu yönetimi, JWT/rol tabanlı erişim, kullanıcı yönetimi, denetim kayıtları, dört programlık karşılaştırma, açıklanabilir otomatik risk kategorileri, sürükle-bırak tercih sıralaması, taslak/versiyon kaydı, kullanıcıya indirilebilir PDF-XLSX-CSV çıktısı, tercih özet raporları, atomik Excel veri sürümü aktarımı ve yedekleme/geri yükleme araçları bulunur.

Öneri kategorisi eşikleri yönetici ekranından değiştirilebilir; öğrenci kayıtları kalıcı silme yerine arşivlenir ve tercih listeleri taslak, tamamlandı veya arşiv durumunda yönetilebilir.

## Hızlı başlangıç

Windows pilotu için en kısa yol:

```text
1. setup_windows.bat
2. start_yks.bat
3. İş bitince stop_yks.bat
```

Başlatıcı backend sağlık kontrolünü yapar ve ardından Windows istemcisini açar. Oturum Windows ve Web’de yeniden açılışlar arasında korunur.

### Uzaktan güncelleme

Yönetici, Sistem Ayarları ekranından HTTPS üzerindeki güncelleme manifest
adresini kaydeder. Manifest `version`, `download_url` ve paketin 64 karakterli
`sha256` değerini içermelidir. Örnek dosya
`docs/UPDATE_MANIFEST_EXAMPLE.json` altındadır.

Yeni paket mevcut temiz dağıtım ZIP'i olmalıdır. Güncelleme kullanıcı onayıyla
başlar; paket doğrulanır, yerel veritabanı yedeklenir ve güncelleme sonrasında
uygulama yeniden açılır. Dağıtım paketindeki boş veritabanı mevcut kullanıcı
veritabanının üzerine yazılmaz.

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
Copy-Item ..\.env.example .env
alembic upgrade head
cd ..
python scripts\import_yks_excel.py "data\2026 YKS TERCİH ROBOTU 25 Temmuz.xlsx"
python scripts\create_admin.py
cd backend
.\.venv\Scripts\uvicorn app.main:app --reload
```

Yeni terminal:

```powershell
cd frontend
flutter pub get
flutter run -d chrome
# veya
flutter run -d windows
```

## Build ve test

```powershell
cd backend
.\.venv\Scripts\pytest
cd ..\frontend
flutter test
flutter build web
flutter build windows
```

PostgreSQL: `docker compose up -d db`. Migration: `cd backend; alembic upgrade head`.

Veritabanı yedeği PostgreSQL için `pg_dump`, geri yükleme `pg_restore` ile yapılır. SQLite geliştirme dosyası uygulama kapalıyken kopyalanabilir.

Uygulama açıldığında sağ üstteki giriş simgesini kullanın. Yönetici hesabının parolası yalnızca `create_admin.py` çalıştırılırken güvenli biçimde sorulur; kaynak kodda veya teslim veritabanında hazır parola bulunmaz.

Tercih listeleri `/api/preference-lists/{id}/export.pdf`, `.xlsx` ve `.csv` uçlarından indirilebilir. CSV/Excel hücreleri formül enjeksiyonuna karşı güvenli hale getirilir; PDF çıktısı gömülü Roboto yazı tipiyle Türkçe karakterleri korur.

## Güvenlik

Kaynak kodda parola yoktur. `.env` sürüm kontrolüne alınmamalıdır. Öğrenci verileri gereksiz kimlik alanı olmadan ve açık rıza işaretiyle tutulur. Üretimde HTTPS, güçlü `SECRET_KEY`, rol yetkileri ve düzenli yedek zorunludur.

> Bu sistem yalnızca karar destek amacıyla hazırlanmıştır. Kesin yerleşme garantisi vermez.
