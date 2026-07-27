# Windows Kurulumu

## Önerilen pilot kurulumu

1. `setup_windows.bat` dosyasına çift tıklayın.
2. Yönetici e-posta, ad ve parolasını komut penceresinde girin.
3. Kurulum bittikten sonra `start_yks.bat` ile uygulamayı açın.
4. Çalışmayı bitirirken `stop_yks.bat` ile yerel backend’i durdurun.

Başlatıcı backend’i `127.0.0.1:8000` üzerinde gizli pencerede çalıştırır, sağlık kontrolü başarılı olduktan sonra Windows uygulamasını açar. Loglar `runtime` klasöründedir.

## Elle kurulum

1. Backend klasöründe `python -m venv .venv` ve `.venv\Scripts\pip install -r requirements.txt`.
2. `.env.example` dosyasını `.env` olarak kopyalayıp gizli anahtarı değiştirin.
3. `alembic upgrade head`.
4. Kök klasörden `python scripts\import_yks_excel.py "data\2026 YKS TERCİH ROBOTU 25 Temmuz.xlsx"`.
5. `python scripts\create_admin.py` ile parolayı komut satırında girerek yöneticiyi oluşturun.
6. Backend: `uvicorn app.main:app --reload` (backend klasöründe).
7. Frontend: `flutter pub get`, ardından `flutter run -d chrome` veya `flutter run -d windows`.

PostgreSQL için kökte `docker compose up -d db`; üretim `DATABASE_URL` değerini PostgreSQL bağlantısına ayarlayın.

## Yedekleme

```powershell
python scripts\backup_database.py
python scripts\restore_database.py backups\yks-YYYYMMDD-HHMMSS.db --yes
```

Scriptler SQLite’ta güvenli dosya kopyası, PostgreSQL’de `pg_dump`/`pg_restore` kullanır. Geri yükleme mevcut veriyi değiştirdiği için açık `--yes` onayı gerektirir.
