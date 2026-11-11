# KlyMusic 2.5.0 (12) — 8 Kasım 2026

[Son CI çalışması](https://github.com/KlyMorias0/KlyMusic/actions/runs/42456215094) başarılı.
Kod: `6e2e59ba28b91ec2f7dfc0c2a41cfd830335c86a`.

- Release iPhoneOS ARM64 cihaz derlemesi geçti. iOS 17.0+, SDK iphoneos26.2, Xcode 26.3. Paket imzasız.
- 45 uygulama birim testi, 3 arayüz testi ve 12 YouTubeKit testi geçti: toplam 60 başarılı test, 0 hata. Bir canlı sağlayıcı tanılaması uygun kayıt bulamadığı için atlandı.
- Tab bar/root ve mini oynatıcı kaynakları orijinal arşivle aynı. LyricsView ve AnimatedLyricLine kaynakları da birebir aynı; ayrı eski lyrics oynatıcı kabuğu kaldırıldı. Güncel koruma kapsamı Protected-UI-Current.json içindedir.
- Arayüz testi, sözler açıldığında oynat/duraklat düğmesinin konum ve boyutunun korunmasını (3 nokta tolerans), söz takibini, satıra dokunarak sarma davranışını, kalite seçimini ve native tab bar gezinmesini doğruladı.
- Hazır sonraki AVPlayerItem'ın yeniden oluşturulmadan kullanıldığı nesne kimliğiyle doğrulandı. Kontrol yolu bu CI örneğinde 1.732 ms sürdü. Bu sayı duyulabilir ses gecikmesi değildir; 1 ms ses veya internetten açılış garantisi verilmez.
- Ekonomik tercih, sıralı kaynak adaylarının kullanılmayan üçüncü adayı başlatmaması, kalıcı doğrulanmış kayıt eşleştirmesi ve eski/yeni yedeklerden veri tercihi geri yükleme testleri geçti.
- Apple kapak URL boyutlandırması ve kapağın iki tarafından farklı renk çıkarma testleri geçti. Örnek kapak yanıtı 600 pikselde 123,760 bayt, 160 pikselde 15,020 bayttır. Bu belirli bir küçük görsel örneğidir; tüm uygulama trafiği veya ses tüketimi ölçümü değildir.
- Oynatıcı, sözler, ana ekran ve ayarlar görüntüleri incelendi. Ekran görüntüleri yerel test sesini/metadata'sını ve Apple katalog örnek kapağını kullanır; gerçek YouTube çalmasını kanıtlamaz. Örnek kapak uygulama paketine dahil değildir.
- IPA ZIP bütünlüğü, SHA256, sürüm/build, cihaz hedefi, ARM64 Mach-O ve imzasız paket yapısı doğrulandı.

## Sınırlar

Gerçek iPhone'da duyulabilir ses geçişi ve toplam mobil veri tüketimi ölçülmedi. Canlı YouTube tanılaması CI'dan çalınabilir bir kayıt bulamadı. Kaynaklar 48 kbps AAC sunarsa ses yükü yaklaşık 21,6 MB/saat, 128 kbps sunarsa yaklaşık 57,6 MB/saattir; katalog, kapak, betik ve protokol trafiği buna eklenir. Ön yükleme süresi AVPlayer'a bir tercihtir, toplam veri için katı bir sınır değildir. Sistem ses seviyesi sürgüsü simülatörde fiziksel cihazdaki gibi görünmeyebilir.

IPA SHA256: `2bae92d2f4f612909186791f8c38f845109372287f391315fbf194c1e4ff0b21`.

Önceki sürümlerin doğrulama dosyaları tarihsel kayıttır. Güncel sonuç bu belgedir.
