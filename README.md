# KlyMusic 2.3.0 (8)

KlyMusic, iOS 17 ve sonrası için SwiftUI ile geliştirilmiş bir müzik uygulamasıdır. Katalog, arama, ses bağlantısı çözümleme ve şarkı sözleri doğrudan telefonda çalışır. Kullanıcı hesabı veya müzik sunucusu adresi girmen gerekmez. Favoriler, çalma listeleri ve indirilen şarkılar cihazda saklanır.

## iPhone'a kurulum

`dist/KlyMusic-unsigned.ipa`, ARM64 iPhone/iPad Release paketidir. İmzasızdır; yüklemeden önce kullandığın sideload aracıyla kendi Apple hesabın üzerinden imzalaman gerekir. Apple ID, parola veya sertifikanı KlyMusic'e girmezsin.

Uygulamayı açınca **Dinle**, **Keşfet**, **Kütüphane** ve **Ara** sekmelerini kullanabilirsin. Bir şarkı seçildiğinde mini oynatıcı açılır. Mini oynatıcıya dokunarak tam oynatıcıya, sözlere ve çalma sırasına geçebilirsin. İndirilen şarkılar **Kütüphane → İndirilenler** içinde internet olmadan oynatılır.

## Bu sürüm

- YouTube Music ana ses kaynağı; Apple başlık, sanatçı, kapak ve süre bilgileri korunur. Birleşik, remix veya süresi farklı kayıtlar reddedilir.
- Ana sayfa, keşfet, arama, kütüphane, koleksiyonlar, ayarlar ve tam ekran oynatıcı yenilendi. Mevcut tab bar ve animasyonlu söz bileşenleri korundu.
- Paylaşılan ses bağlantısı önbelleği, sınırlı görünür parça ön hazırlığı ve sıradaki parçanın önceden hazırlanması eklendi. Alternatif YouTube ses kaynakları korunuyor.
- Telefon dili Türkçeyse Türkiye listeleri ve Türkçe keşif seçkileri öne çıkar.
- YouTube dosyalarında yanlış raporlanan kapsayıcı süresi, sesin tamamı doğrulandıktan sonra yeniden kodlamadan düzeltilir; gerçekten farklı uzunluktaki dosyalar kesilerek kabul edilmez.

- Koyu temayla başlayan, açık ve sistem temasını da destekleyen yenilenmiş ana ekran, keşif ve kütüphane.
- iOS 26'da sistemin Liquid Glass sekme çubuğu, ayrı arama sekmesi ve sekme aksesuarında mini oynatıcı; eski sürümlerde standart iOS sekmeleri.
- Tam oynatıcı, konum çubuğu, karıştırma, tekrar, sıradaki çal ve düzenlenebilir çalma sırası.
- Zamanlı sözler varsa otomatik satır takibi ve satıra dokunarak sarma; düz söz alternatifi.
- Favoriler, çalma listeleri, sanatçı takibi, son aramalar ve kaldığın yerden devam.
- Şarkı indirme, duraklatma/devam, yeniden deneme, Wi-Fi tercihi ve çevrimdışı dinleme. Arka plan tamamlama bildirimi ses doğrulaması ve kütüphane kaydını bekler; yeniden açılan oturumun tamamlanmış indirmesi de kurtarılır.
- Arka plan sesi, kilit ekranı kontrolleri, AirPlay ve uyku zamanlayıcısı.
- Kütüphaneyi JSON olarak yedekleme ve birleştirerek geri yükleme. Ses dosyaları yedeğe dahil edilmez.

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
