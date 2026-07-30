# 2026 YKS Tercih Robotu istemcisi

Windows, web, Android ve iOS için ortak Flutter istemcisidir.

API adresi derleme sırasında `API_URL` değeriyle verilir:

```text
flutter build web --release --dart-define=API_URL=
flutter build apk --release --dart-define=API_URL=https://uygulama.example.com
```

Web sürümünde boş API adresi, arayüz ile API aynı alan adından sunulduğunda
`/api` yollarını kullanır. Android ve iOS mağaza paketlerinde HTTPS adresi
zorunludur.

Mobil uygulama kimliği:

```text
tr.com.ugurguduk.yks_tercih_robotu
```
