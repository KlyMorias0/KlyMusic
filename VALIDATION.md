2.13.0 kaynak adayı: [kısmi doğrulama ve Mac engeli](VALIDATION-2.13.0.md). Son doğrulanmış iPhone sürümü 2.12.0.

Güncel sürüm: [KlyMusic 2.12.0 doğrulaması](VALIDATION-2.12.0.md). Aşağıdaki kayıt 2.3.0 sürümüne aittir.

# KlyMusic 2.3.0 (8) doğrulama — 6 Kasım 2026

ARM64 iPhone/iPad Release derlemesi ve son kaynaklarla simülatör test derlemesi geçti. IPA iOS 17+ içindir. ZIP bütünlüğü, sürüm, cihaz platformu, gerekli kaynaklar ve Release ikilisiyle birebir eşleşme doğrulandı.

36 birim testi geçti. Önbelleğin istek paylaşımı, iptal güvenliği, süre sonu ve LRU kontrolleri bu 36 testin içindedir. Sözleri takip etme ve söz satırından ileri sarma arayüz testi de geçti. Bu çalıştırma gezinme sırasında sohbet kesilince durdu; tamamlanan testlerin başarılı sonuçları günlükte kayıtlıdır.

Kalan açık/koyu tema gezinme testi ayrı çalıştırmada başarıyla tamamlandı: sekmeler, Favoriler, arama, ayarlar ve geri dönüşler doğrulandı. İki arayüz testi ayrı çalıştırmalarda geçmiştir; tamamlanmış tek bir 38 testlik oturum iddiası yoktur. Ayrıca YouTubeKit yardımcı işlevlerinde 6 test geçti.

Tab bar/uygulama kabuğu, mini oynatıcı ve söz bileşenleri önceki kaynaklarla SHA-256 düzeyinde birebir aynı. Canlı ses kontrolünde kullanılan kaynakların ve teslim edilen kaynakların SHA-256 değerleri eşleşiyor.

Son canlı BLOK3 “Kayıp Kalp” kontrolü YouTube AAC/m4a ile geçti: beklenen süre 153.231 saniye, doğrulanan süre 153.23 saniye. Soğuk çözümleme 8.85 saniye, aynı kayda hemen yapılan önbellek isteği yaklaşık 0.00023 saniyeydi. Bu tek macOS örneğidir; iPhone şarkı geçiş süresinin ölçümü değildir.

Fiziksel iPhone kurulumu, kilit ekranı/Bluetooth davranışı ve gerçek cihaz geçiş gecikmesi henüz denenmedi. IPA imzasızdır; kullandığın sideload aracıyla imzalanmalıdır.

Ayrıntılı kayıtlar kaynak ZIP'indeki Build-Verification.json, Regression-Verification.json, Navigation-Test-Summary.json, Live-Playback-Verification.json ve Protected-UI-Verification.json dosyalarındadır.
