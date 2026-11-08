# KlyMusic 2.4.1 (11)

KlyMusic, iOS 17 ve sonrası için SwiftUI ile geliştirilmiş bir müzik uygulamasıdır. Katalog, arama, ses bağlantısı çözümleme ve şarkı sözleri doğrudan telefonda çalışır. Kullanıcı hesabı veya müzik sunucusu adresi girmen gerekmez. Favoriler, çalma listeleri ve indirilen şarkılar cihazda saklanır.

## iPhone'a kurulum

`dist/KlyMusic-unsigned.ipa`, ARM64 iPhone/iPad Release paketidir. İmzasızdır; yüklemeden önce kullandığın sideload aracıyla kendi Apple hesabın üzerinden imzalaman gerekir. Apple ID, parola veya sertifikanı KlyMusic'e girmezsin.

Uygulamayı açınca **Dinle**, **Keşfet**, **Kütüphane** ve **Ara** sekmelerini kullanabilirsin. Bir şarkı seçildiğinde mini oynatıcı açılır. Mini oynatıcıya dokunarak tam oynatıcıya, sözlere ve çalma sırasına geçebilirsin. İndirilen şarkılar **Kütüphane → İndirilenler** içinde internet olmadan oynatılır.

## Bu sürüm — 8 Kasım 2026

- Saf siyah zemin, standart başlıklar ve kapakların öne çıktığı Apple Music benzeri düzen. Önceki taslakta kullanılan mavi/gri zemin, sloganlar ve renkli gösterge kartları kaldırıldı.
- Tam oynatıcıda büyük kare kapak, altında şarkı/sanatçı bilgisi, ince sarma çubuğu, çerçevesiz geri/oynat/ileri kontrolleri, sistem ses seviyesi ve altta sözler/AirPlay/çalma sırası.
- Tab bar, mini oynatıcı, lyrics bileşenleri ve lyrics açıkken kullanılan tam düzen orijinal arşivle birebir korunur. Kontrol kaydı: `Protected-UI-Current.json`.
- Ses çözümleme artık bütün istemcilerin tamamlanmasını beklemek yerine doğrulanan ilk AAC bağlantısını kullanır. Başlık, sanatçı, süre ve medya başlığı doğrulamaları korunur.
- Büyük YouTube player JavaScript'inin işlenmiş hali paylaşılır; eşzamanlı isteklerin aynı dosyayı tekrar tekrar işlemesi önlenir. Player betiği önbelleği eşzamanlı erişime güvenlidir.
- Şarkı, aday kayıt ve istemci istekleri iptali destekler. Paylaşılan çalma önbelleği, görünür şarkıların ön hazırlığı, sonraki parça hazırlığı ve çevrimdışı indirmeler korunur.

Gerçek iPhone'da açılış süresi ölçülmedi. CI'daki canlı kaynak denemesi kullanılabilir bir kayıt bulamadığından 20 saniyeden belirli bir süreye düşüş iddiası yoktur. Güncel test ve derleme durumu `VALIDATION-2026-11-08.md` içinde kaydedilir. Önceki tarihli doğrulama dosyaları önceki sürümlerin kayıtlarıdır.

## Xcode ile çalıştırma

Test edilen araç sürümü **Xcode 26.3**. Bu sürümle `ios/KlyMusic.xcodeproj` dosyasını açıp **KlyMusic** şemasını seç. Kullanılan `tabViewBottomAccessory(isEnabled:)` API’si Xcode 26.0 SDK’sında bulunmadığından derleme için Xcode 26.3 kullan. Simülatör doğrudan müzik kaynaklarına bağlanır; Python sunucusu başlatman gerekmez. Gerçek cihaza Xcode üzerinden yüklemek için kendi imzalama takımını seç ve cihaz yapılandırmasında `CODE_SIGNING_ALLOWED` ayarını `YES` yap. Teslim edilen IPA, sideload için imzasız üretilir.

Cihaz IPA'sını yeniden üretmek için:

```sh
KLYMUSIC_BUILD_DIR=/tmp/KlyMusicBuild bash scripts/build-ipa.sh
```

XcodeGen yalnızca `ios/project.yml` değiştikten sonra projeyi yeniden oluşturmak için gerekir. Yerel YouTubeKit paketi `ios/Packages/YouTubeKit` içinde teslim edilir.

## Geliştirme ve testler

Xcode'da **Product → Test** ile birim ve arayüz testlerini çalıştır. Otomatik testler kaynak eşleştirme, söz zamanları, kuyruk, yedekleme, hızlı parça seçimi ve gezinme gibi akışları kapsar. Çevrimiçi testler sağlayıcıların erişilebilir olmasına bağlıdır. Bu teslimatta gerçekten tamamlanan kontroller `VALIDATION.md` içinde kayıtlıdır.

`server/`, `compose.yaml` ve `scripts/run-server.sh` eski sunucu mimarisinin geliştirme araçlarıdır. Release IPA bunları kullanmaz. Yalnızca Debug derlemesinde `-serverURL http://127.0.0.1:8787` başlatma argümanı verilirse geliştirme sunucusu devreye girer.

Görsel söz takibi ve satırdan sarma akışını sağlayıcı bağlantısından bağımsız denemek için `bash scripts/test-ios.sh` çalıştır. Bu komut yerel test verisi sunucusunu açar; birim testlerini, yerel sekme gezinmesini ve zamanlı söz testini çalıştırır. Test bitince test sunucusu kapanır. Bu sunucu yalnızca otomasyon içindir; uygulamanın kullanımı için gerekli değildir. Hedef simülatörü `KLYMUSIC_TEST_DESTINATION` ile değiştirebilirsin.

## Kaynak davranışı

Katalog ve kapaklar Apple'ın herkese açık uç noktalarından; oynatılabilir ses öncelikle YouTube Music eşleştirmesinden (elle kaynak seçilirse JioSaavn bağlayıcısından); sözler LRCLIB'den alınır. Aynı kaydın sanatçı, başlık ve süre eşleşmesi kontrol edilir. Uygun tam kayıt bulunamazsa açık bir hata gösterilir; kısa önizleme tam şarkı gibi sunulmaz. Kaynak erişimi bölgeye ve sağlayıcı değişikliklerine göre farklılık gösterebilir.

Cihazdaki veriler ve ağ istekleri için `PRIVACY.md`; doğrulanan ve cihazda henüz denenmeyen davranışlar için `VALIDATION.md` dosyasına bak.
