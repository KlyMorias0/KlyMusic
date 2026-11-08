# 8 Kasım 2026 — KlyMusic 2.4.1 (11)

Kod: `e0e7c82aa7386a9d80997ebd51b2378de4d7e8e5`.
[GitHub Actions çalışması](https://github.com/KlyMorias0/KlyMusic/actions/runs/42453648513) başarılı.

- Xcode 26.3 ile Release iPhoneOS ARM64 cihaz derlemesi geçti. iOS 17+; IPA imzasızdır.
- 39 uygulama birim testi geçti; 1 isteğe bağlı canlı kaynak tanılama testi atlandı; 0 hata.
- 3 arayüz testi geçti: açık/koyu tema yerel sekme gezinmesi; lyrics takibi/satırdan sarma; yenilenen ekranlar ve tam oynatıcı.
- 12 YouTubeKit ayrıştırıcı/çıkarım testi geçti; 0 hata.
- Toplam 54 test geçti, 1 canlı tanılama testi atlandı.
- Tab bar/root, mini oynatıcı, LyricsView/AnimatedLyricLine ve lyrics açıkken kullanılan orijinal düzen, 7 Kasım arşiviyle birebir aynı. Ayrıntılar `Protected-UI-Current.json` içinde.
- Ekran görüntüleri kontrol edildi: koyu temada saf siyah zemin, standart başlıklar ve Apple Music referansına yakın oynatıcı kontrolleri. Önceki taslağın sloganları ve mavi/gri zemini kaldırıldı.
- IPA ZIP bütünlüğü, SHA256, ARM64 Mach-O, iPhoneOS hedefi, sürüm/build ve imzasız paket yapısı kontrol edildi.

## Sınırlar

Gerçek iPhone üzerinde test ve şarkı açılış süresi ölçümü yapılmadı. CI'daki canlı Tarkan/Kuzu Kuzu tanılaması oynatılabilir kayıt elde edemediği için atlandı. Gerçek sesin veya 20 saniyelik gecikmenin belirli bir süreye indiği iddia edilmiyor.

Yerel test sunucusu ekran ve oynatma akışlarını harici sağlayıcı erişiminden bağımsız sınar. Ekran görüntülerindeki “Gece Yolu / KlyMusic Test” test verisidir; kapak görselinin kaynağı `scripts/fixtures/cover-source.json` içindedir. Bu örnek kapak uygulama paketine dahil değildir. Sistem ses seviyesi sürgüsü simülatörde gerçek cihazdaki gibi görünmeyebilir.

IPA SHA256: `54852dde6d38015df3bce7defa2e7e775a92d7459466d81805dfa9896fac9552`.

Önceki tarihli JSON/Markdown/log dosyaları önceki sürümlere aittir; güncel sonuçlar bu belgededir.
