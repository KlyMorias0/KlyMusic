# KlyMusic 2.12.0 (19)

KlyMusic, iOS 17 ve sonrası için SwiftUI ile geliştirilmiş bir müzik uygulamasıdır. Katalog, arama, ses bağlantısı çözümleme ve şarkı sözleri doğrudan telefonda çalışır. Kullanıcı hesabı veya müzik sunucusu adresi girmen gerekmez. Favoriler, çalma listeleri ve indirilen şarkılar cihazda saklanır.

## iPhone'a kurulum

`dist/KlyMusic-unsigned.ipa`, ARM64 iPhone/iPad Release paketidir. İmzasızdır; yüklemeden önce kullandığın sideload aracıyla kendi Apple hesabın üzerinden imzalaman gerekir. Apple ID, parola veya sertifikanı KlyMusic'e girmezsin.

Uygulamayı açınca **Dinle**, **Keşfet**, **Kütüphane** ve **Ara** sekmelerini kullanabilirsin. Yeni liste oluşturmak için **Kütüphane → … → Yeni Çalma Listesi…** yolunu izle. Bir şarkı seçildiğinde mini oynatıcı açılır. Mini oynatıcıya dokunarak tam oynatıcıya, sözlere ve çalma sırasına geçebilirsin. İndirilen şarkılar **Kütüphane → İndirilenler** içinde internet olmadan oynatılır.

## Bu sürüm — 2.12.0

- **Birden fazla söz kaynağı:** LRCLIB tam kayıt ve alternatif kayıt araması, ardından Lyrics.ovh düz metin yedeği kullanılır. Albüm baskısı veya yazımı yüzünden kaçan kayıtlar başlık, sanatçı ve süreyle kontrol edilir.
- **Gerçek zamanlı sözler:** Doğrulanmış zaman damgaları varsa mevcut satır akışı kullanılır. Düz sözler de gösterilir; onlara yapay zaman damgası eklenmez. Zamanlı sonuç düz metne tercih edilir. Yanlış sanatçı, farklı sürüm ve bilinen süre uyuşmazlığı reddedilir.
- **Daha güncel önbellek:** Önceki söz dosyaları okunur ve yenilenir. Zamanlı sözler 7 gün, düz sözler 24 saat, enstrümantal sonuçlar 6 saat sonra kontrol edilir. Kayıtlı sözler yenileme sırasında görünür kalır; ağ hatası veya boş yanıt eldeki sözleri silmez. Mevcut zamanlı söz düz/enstrümantal sonuca düşürülmez.
- **Yeniden deneme:** Boş/bozuk sonuç kalıcı söz kaydı sayılmaz; söz sayfası yeniden açıldığında tekrar denenebilir. Bağlantı hatalarında mevcut Yeniden dene düğmesi kullanılır.
- **Veri tasarrufu:** Bu modda ilk LRCLIB isteği zamanlı söz bulursa başka söz isteği gönderilmez. Gerektiğinde yedek kaynaklar devreye girer; taze önbellek ağ isteğini önler. İndirme sonrası boş sonuç da kayıtlı çevrimdışı sözlerin üzerine yazılmaz.
- **Onaylanan tasarım aynı:** Oynatıcı, mini oynatıcı, söz akışı/animasyonu, native tab bar, sıra, oynatıcı menüsü ve kapak/arka plan kaynakları 2.7.0 tabanıyla aynıdır. SwiftData şeması değişmedi. 2.11.0 ses eşleştirme/çözümleme davranışı korunur.

Spotify veya onun söz sağlayıcısından veri alınmaz. Spotify'da söz bulunan her kaydın bu iki kaynakta da bulunması garanti değildir. Kaynak erişimi ve zamanlı söz kapsamı parçaya/bölgeye göre değişebilir. Apple Music ile piksel eşitliği, iOS 27 veya fiziksel iPhone doğrulaması yoktur.

Ses tüketimi kaynak bit hızına bağlıdır. Örneğin 48 kbps AAC yaklaşık 21,6 MB/saat, 128 kbps yaklaşık 57,6 MB/saat ses verisidir; bunlar ölçülmüş toplam uygulama trafiği veya üst sınır değildir. Kapak, arama ve protokol trafiği ayrıca oluşur. Veri tercihi indirmelerde ve yedek/geri yüklemede de korunur.

Güncel doğrulama `VALIDATION-2.12.0.md` içinde kaydedilir. Önceki doğrulama belgeleri önceki sürümlere aittir.

## Xcode ile çalıştırma

Test edilen araç sürümü **Xcode 26.3**. Bu sürümle `ios/KlyMusic.xcodeproj` dosyasını açıp **KlyMusic** şemasını seç. Kullanılan `tabViewBottomAccessory(isEnabled:)` API’si Xcode 26.0 SDK’sında bulunmadığından derleme için Xcode 26.3 kullan. Simülatör doğrudan müzik kaynaklarına bağlanır; Python sunucusu başlatman gerekmez. Gerçek cihaza Xcode üzerinden yüklemek için kendi imzalama takımını seç ve cihaz yapılandırmasında `CODE_SIGNING_ALLOWED` ayarını `YES` yap. Teslim edilen IPA, sideload için imzasız üretilir.

Cihaz IPA'sını yeniden üretmek için:

```sh
KLYMUSIC_BUILD_DIR=/tmp/KlyMusicBuild bash scripts/build-ipa.sh
```

XcodeGen yalnızca `ios/project.yml` değiştikten sonra projeyi yeniden oluşturmak için gerekir. Yerel YouTubeKit paketi `ios/Packages/YouTubeKit` içinde teslim edilir.

## Geliştirme ve testler

Xcode'da **Product → Test** ile birim ve arayüz testlerini çalıştır. Otomatik testler kaynak eşleştirme, söz zamanları, kuyruk, yedekleme, hızlı parça seçimi ve gezinme gibi akışları kapsar. Çevrimiçi testler sağlayıcıların erişilebilir olmasına bağlıdır. Bu teslimatta gerçekten tamamlanan kontroller `VALIDATION-2.12.0.md` içinde kayıtlıdır.

`server/`, `compose.yaml` ve `scripts/run-server.sh` eski sunucu mimarisinin geliştirme araçlarıdır. Release IPA bunları kullanmaz. Yalnızca Debug derlemesinde `-serverURL http://127.0.0.1:8787` başlatma argümanı verilirse geliştirme sunucusu devreye girer.

Görsel söz takibi ve satırdan sarma akışını sağlayıcı bağlantısından bağımsız denemek için `bash scripts/test-ios.sh` çalıştır. Bu komut yerel test verisi sunucusunu açar; birim testlerini, yerel sekme gezinmesini ve zamanlı söz testini çalıştırır. Test bitince test sunucusu kapanır. Bu sunucu yalnızca otomasyon içindir; uygulamanın kullanımı için gerekli değildir. Hedef simülatörü `KLYMUSIC_TEST_DESTINATION` ile değiştirebilirsin.

## Kaynak davranışı

Katalog ve kapaklar Apple'ın herkese açık uç noktalarından; oynatılabilir ses öncelikle YouTube Music eşleştirmesinden (gerekirse aynı kaydı doğrulayan alternatif bağlayıcıdan); sözler LRCLIB ve Lyrics.ovh üzerinden alınır. Aynı kaydın sanatçı, başlık ve süre eşleşmesi kontrol edilir. Uygun tam kayıt bulunamazsa açık bir hata gösterilir; kısa önizleme tam şarkı gibi sunulmaz. Kaynak erişimi bölgeye ve sağlayıcı değişikliklerine göre farklılık gösterebilir.

Cihazdaki veriler ve ağ istekleri için `PRIVACY.md`; doğrulanan ve cihazda henüz denenmeyen davranışlar için `VALIDATION-2.12.0.md` dosyasına bak.
