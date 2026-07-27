# API

FastAPI etkileşimli belge: `http://localhost:8000/docs`

- `GET /health`
- `GET /api/dashboard`
- `GET /api/programs`: q, level, city, score_type, min_rank, max_rank, page, page_size
- `GET /api/programs/{id}`
- `POST /api/recommend?student_rank=...&program_id=...`
- `POST /api/recommend/batch?student_id=...&score_type=...`: gövdede program kimlikleri
- `GET/POST /api/students`
- `PUT /api/students/{id}`
- `DELETE /api/students/{id}`: kalıcı silme yerine arşivleme
- `POST /api/auth/login`: OAuth2 formunda `username` alanına e-posta yazılır
- `GET /api/auth/me`
- `POST /api/users`: yalnız yönetici
- `GET /api/users`: yalnız yönetici
- `PATCH /api/users/{id}`: rol, aktiflik, ad veya parola; yalnız yönetici
- `POST /api/preference-lists`
- `GET /api/preference-lists/{id}`
- `PUT /api/preference-lists/{id}`: durum ve sıralı içerik güncelleme
- `POST /api/preference-lists/{id}/versions`
- `GET /api/preference-lists/{id}/export.pdf`
- `GET /api/preference-lists/{id}/export.xlsx`
- `GET /api/preference-lists/{id}/export.csv`
- `GET /api/preference-lists?student_id=...`
- `GET /api/students/{id}/exam-results`
- `POST /api/students/{id}/exam-results`
- `GET /api/students/{id}/notes`
- `POST /api/students/{id}/notes`
- `GET /api/reports/summary`
- `GET /api/audit-logs`: filtreli ve sayfalı, yalnız yönetici
- `GET /api/settings/recommendation-thresholds`
- `PUT /api/settings/recommendation-thresholds`: yalnız yönetici
- `GET /api/imports`: veri sürümü geçmişi, yalnız yönetici
- `POST /api/imports/preview`: multipart `.xlsx` doğrulama, yalnız yönetici
- `POST /api/imports/commit?data_year=...`: doğrulama, upsert, sürüm ve audit kaydı; yalnız yönetici

`GET /api/programs/{id}` yanıtı 2018–2025 `rank_history` listesini de içerir. Sayısal başarı sırası ile `Yeni`, `Dolmadı` ve benzeri durumlar ayrı alanlarda döner.

Korumalı uçlarda `Authorization: Bearer <token>` başlığı kullanılır. Roller: `admin`, `counselor`, `teacher`, `viewer`.

Program arama; düzey, şehir, puan türü, üniversite türü, dil, öğretim şekli, ücret, akreditasyon, yerleşme durumu, kontenjan ve başarı sırası aralıklarını birlikte destekler.
