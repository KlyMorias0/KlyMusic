# KlyMusic 2.5.0 (12)

KlyMusic, iOS 17 ve sonrası için SwiftUI ile geliştirilmiş bir müzik uygulamasıdır. Katalog, arama, ses bağlantısı çözümleme ve şarkı sözleri doğrudan telefonda çalışır. Kullanıcı hesabı veya müzik sunucusu adresi girmen gerekmez. Favoriler, çalma listeleri ve indirilen şarkılar cihazda saklanır.

## iPhone'a kurulum

`dist/KlyMusic-unsigned.ipa`, ARM64 iPhone/iPad Release paketidir. İmzasızdır; yüklemeden önce kullandığın sideload aracıyla kendi Apple hesabın üzerinden imzalaman gerekir. Apple ID, parola veya sertifikanı KlyMusic'e girmezsin.

Uygulamayı açınca **Dinle**, **Keşfet**, **Kütüphane** ve **Ara** sekmelerini kullanabilirsin. Bir şarkı seçildiğinde mini oynatıcı açılır. Mini oynatıcıya dokunarak tam oynatıcıya, sözlere ve çalma sırasına geçebilirsin. İndirilen şarkılar **Kütüphane → İndirilenler** içinde internet olmadan oynatılır.

## Bu sürüm — 2.5.0

- Kapak ve sözler aynı oynatıcı kabuğunu paylaşır. Sözlere geçince yalnızca kapak alanı değişir; metadata, sarma çubuğu, kontroller ve arka plan yerinde kalır. Eski ayrı lyrics oynatıcı düzeni tamamen kaldırıldı.
- Native tab bar ve mini oynatıcı korunur. LyricsView/AnimatedLyricLine kaynakları, söz takibi, otomatik kaydırma, satırdan sarma ve satır animasyonu orijinal arşivle birebir aynı kalır. Korunan alanlar `Protected-UI-Current.json` içindedir.
- Kenarlardaki ışıklar gerçek kapak piksellerinden hesaplanır. Ana ekran, tam oynatıcı ve ayarlar bu renkleri kullanır. Yeni ayarlar iki gerçek kalite seçeneği, görünüm tercihi, çevrimdışı müzik ve yedekleme alanlarından oluşur.
- Varsayılan **Az veri** modu düşük bit hızlı, cihazda oynatılabilen AAC kopyasını tercih eder. Dengeli adı altında aynı yüksek kaliteyi seçen ayrı bir seçenek sunulmaz. Yüksek kalite isteğe bağlıdır.
- Az veri modunda ekran taraması sırasında ses ön hazırlığı yapılmaz. Yalnızca sıradaki parça hazırlanır; ikinci sonraki parçanın ön hazırlığı kaldırılır. Diğer modda da tarama ön hazırlığı kısıtlı/pahalı bağlantıda çalışmaz.
- Daha önce doğrulanan kayıt eşleşmeleri 7 gün saklanır. Tekrar dinlemede başlık/sanatçı eşleştirmesi tekrar aranmaz; süresi dolan CDN bağlantıları kalıcı olarak saklanmaz. Kimlik ve süre değişmişse eşleşme yeniden doğrulanır.
- Küçük Apple kapakları artık görünüm boyutuna uygun istenir. Renk çıkarımı ek bir bağımsız indirme yapmak yerine aynı kapak önbelleğini paylaşır; çevrimdışı sabitlenmiş eski kapaklar da kullanılabilir.
- Hazır kuyruk öğesi yeniden oluşturulmadan sonraki şarkıya geçirilir. **1 ms duyulabilir ses geçişi veya internetten ilk açılış garantisi verilmez.** Kontrol yolunun süresi sesin duyulma süresi değildir.

Ses tüketimi kaynak bit hızına bağlıdır. Örneğin 48 kbps AAC yaklaşık 21,6 MB/saat, 128 kbps yaklaşık 57,6 MB/saat ses verisidir; bunlar ölçülmüş toplam uygulama trafiği veya üst sınır değildir. Kapak, arama ve protokol trafiği ayrıca oluşur. Veri tercihi indirmelerde ve yedek/geri yüklemede de korunur.

Güncel doğrulama `VALIDATION-2.5.0.md` içinde kaydedilir. Önceki doğrulama belgeleri önceki sürümlere aittir.

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
