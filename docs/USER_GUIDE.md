# Kullanıcı Kılavuzu

Windows pilotunda `start_yks.bat` dosyasına çift tıklayın. Backend ve Windows uygulaması birlikte açılır. İlk kurulum daha önce yapılmadıysa önce `setup_windows.bat` çalıştırılmalıdır. Oturum belirteci uygulama yeniden açıldığında korunur; sağ üstteki çıkış simgesi güvenli oturumu temizler.

Sol menüden program arama, öğrenci yönetimi, karşılaştırma, tercih listesi ve raporlara ulaşılır.

1. Sağ üstteki giriş simgesinden yönetici veya yetkili kullanıcı hesabıyla giriş yapın.
2. Öğrenciler ekranında öğrenci kaydını oluşturun.
   Öğrenci kartına tıklayarak tarih ve yazar bilgisiyle görüşme notu ekleyin.
3. Program Ara ekranında gelişmiş filtreleri kullanarak şehir, puan türü, 2025 yerleşme durumu, akreditasyon ve başarı sırası aralığını daraltın. Programın işlem menüsünü açarak tercih listesine veya karşılaştırmaya ekleyin.
   Program satırına tıklayarak 2018–2025 başarı sırası grafiğini, sayısal olmayan yıl durumlarını ve özel koşulları inceleyin.
4. Karşılaştırma ekranında en fazla dört programı üniversite, şehir, ücret, dil, kontenjan, sıralama ve akreditasyon bakımından inceleyin.
5. Tercih Listesi ekranında öğrenciyi, puan türünü ve öğrencinin 2026 başarı sırasını girin. “Analiz et” seçeneği programları otomatik risk kategorilerine ayırır ve gerekçeyi gösterir.
6. Kartları sürükleyerek sıralayın; puan türü uyuşmazlığı uyarılarını kontrol edin. “Taslağı kaydet” düğmesiyle listeyi veritabanına kaydedin.
7. “Kayıtlı listeler” üzerinden eski sürümleri açın veya yeni sürüm oluşturun.
   Açılan liste penceresindeki PDF, Excel ve CSV düğmeleriyle çıktıyı bilgisayarınıza kaydedin.
   Listeyi “Tamamlandı” olarak işaretleyebilir veya arşivleyebilirsiniz. Analiz edilen listenin tamamı aynı risk grubundaysa sistem denge uyarısı verir.
8. Raporlar ekranında tercih sayıları, risk kategorileri ve en çok tercih edilen üniversite/program dağılımlarını inceleyin.
9. Yönetici rolüyle “Excel Veri Aktarımı” ekranında yeni `.xlsx` dosyasını seçin. Önizleme; iki sayfanın kayıt sayılarını, yinelenen kodları ve dosya hash değerini veritabanına yazmadan doğrular. Dosya uygunsa veri yılını girip “Aktarımı onayla” seçeneğini kullanın. Aynı dosya ikinci kez kabul edilmez; önceki veri sürümü geçmişte korunur.
10. “Kullanıcı Yönetimi” ekranında yönetici, rehber öğretmen, öğretmen ve görüntüleyici hesaplarını oluşturun; rolleri veya aktiflik durumlarını yönetin.
11. “Denetim Kayıtları” ekranında kullanıcı, işlem, varlık ve tarih bilgilerini inceleyin.
12. “Sistem Ayarları” ekranında yüksek hedef, hedef aralığı ve dengeli kategori eşiklerini yüzde olarak yönetin.

Rehber öğretmen yalnız kendisine atanmış öğrencileri görebilir ve düzenleyebilir. Görüntüleyici veri değiştiremez. Kullanıcı ve denetim ekranları yalnız yönetici rolüne açıktır.

Öğrenci kartındaki görüşme penceresinden öğrenci arşivlenebilir. Arşivlenen öğrenci aktif listelerden çıkar; kayıt doğrudan kalıcı olarak silinmez.

Öğrenci sıralamasında küçük sayı daha iyidir. Kategoriler olasılık garantisi değil, karar desteğidir. Her zaman güncel ÖSYM/YÖK kılavuzu ve özel koşullar kontrol edilmelidir.
