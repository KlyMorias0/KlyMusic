# KlyMusic 2.9.0 (16)

KlyMusic, iOS 17 ve sonrası için SwiftUI ile geliştirilmiş bir müzik uygulamasıdır. Katalog, arama, ses bağlantısı çözümleme ve şarkı sözleri doğrudan telefonda çalışır. Kullanıcı hesabı veya müzik sunucusu adresi girmen gerekmez. Favoriler, çalma listeleri ve indirilen şarkılar cihazda saklanır.

## iPhone'a kurulum

`dist/KlyMusic-unsigned.ipa`, ARM64 iPhone/iPad Release paketidir. İmzasızdır; yüklemeden önce kullandığın sideload aracıyla kendi Apple hesabın üzerinden imzalaman gerekir. Apple ID, parola veya sertifikanı KlyMusic'e girmezsin.

Uygulamayı açınca **Dinle**, **Keşfet**, **Kütüphane** ve **Ara** sekmelerini kullanabilirsin. Yeni liste oluşturmak için **Kütüphane → … → Yeni Çalma Listesi…** yolunu izle. Bir şarkı seçildiğinde mini oynatıcı açılır. Mini oynatıcıya dokunarak tam oynatıcıya, sözlere ve çalma sırasına geçebilirsin. İndirilen şarkılar **Kütüphane → İndirilenler** içinde internet olmadan oynatılır.

## Bu sürüm — 2.9.0

- **Ayarlar:** İri gri grup kutuları kaldırıldı. Düz zeminde başlıklar, ince ayırıcılar ve daha sakin satırlar kullanılır; kalite, indirme, tema/dil, yedek ve geçmiş işlemleri korunur. Ayarları açan simge artık işleviyle uyumlu sürgü simgesidir.
- **Ana sayfa:** Raf okları başlık satırına hizalandı; açıklama ayrı satırdadır. Öneriler dinlediğin en fazla dört sanatçıdan dönüşümlü gelir; tek sanatçı ilk rafı doldurmaz. Katalog istekleri paralel ve önbelleklidir; ses ön yükleme kuralları aynı kalır.
- **Sanatçı:** Büyük sanatçı adı görünürken üst çubukta tekrarlanmaz. Ad kaydırılıp ekran dışına çıktığında üst başlık görünür. Takip yıldızı üst çubuktadır; çal/karıştır düğmeleri tam genişliği paylaşır.
- **Arama:** Tümü / Şarkılar / Albümler / Sanatçılar filtreleri daha kısa, seçili filtre ters renklerle daha belirgindir. Native arama ve kapsam çubuğu korunur.
- **Kütüphane:** Albümler ve çalma listeleri tek eklenme sırasındadır; aynı albümün şarkıları tek kartta birleşir. Yeniden dinleme eklenme tarihini değiştirmez. Başlık veya sanatçı sıralaması seçilebilir. **… → Düzenle** içinden kategorileri gizleyebilir ve sürükleyerek sıralayabilirsin; düzen yeniden açılışta saklanır.
- Yeni yedekler şarkı eklenme ve liste oluşturma tarihlerini de taşır. Eski yedekler açılabilir. SwiftData şeması değişmedi. Eski kayıtlarda gerçek eklenme tarihi olmadığı için mevcut sıralama ve son dinleme verisiyle bir kez tahmini tarihler atanır; yeni kayıtların gerçek eklenme zamanı saklanır.
- **Onaylanan oynatıcı, tab bar, şarkı sözleri/akışı, çalma sırası ve oynatıcı menüsü kaynak düzeyinde aynıdır.** NowPlaying.swift, KlyMusicApp.swift, Artwork.swift ve TrackMenu, 2.7.0 tabanıyla birebir korunmuştur. Ayrıntılar `Protected-UI-Current.json` içindedir.

Önceki sürümün kayıt eşleştirme, az veri, önbellek ve sonraki parçayı hazırlama davranışları korunur. Bu sürüm ses çözümleme hattını değiştirmez. Bir saniyede duyulabilir başlangıç veya tüm katalog kayıtlarının çalması garantisi verilmez. Apple Music görsel dili referans alınır; iOS 27 veya fiziksel cihazda piksel eşitliği doğrulanmış değildir.

Ses tüketimi kaynak bit hızına bağlıdır. Örneğin 48 kbps AAC yaklaşık 21,6 MB/saat, 128 kbps yaklaşık 57,6 MB/saat ses verisidir; bunlar ölçülmüş toplam uygulama trafiği veya üst sınır değildir. Kapak, arama ve protokol trafiği ayrıca oluşur. Veri tercihi indirmelerde ve yedek/geri yüklemede de korunur.

Güncel doğrulama `VALIDATION-2.9.0.md` içinde kaydedilir. Önceki doğrulama belgeleri önceki sürümlere aittir.

## Xcode ile çalıştırma

Test edilen araç sürümü **Xcode 26.3**. Bu sürümle `ios/KlyMusic.xcodeproj` dosyasını açıp **KlyMusic** şemasını seç. Kullanılan `tabViewBottomAccessory(isEnabled:)` API’si Xcode 26.0 SDK’sında bulunmadığından derleme için Xcode 26.3 kullan. Simülatör doğrudan müzik kaynaklarına bağlanır; Python sunucusu başlatman gerekmez. Gerçek cihaza Xcode üzerinden yüklemek için kendi imzalama takımını seç ve cihaz yapılandırmasında `CODE_SIGNING_ALLOWED` ayarını `YES` yap. Teslim edilen IPA, sideload için imzasız üretilir.

Cihaz IPA'sını yeniden üretmek için:

```sh
KLYMUSIC_BUILD_DIR=/tmp/KlyMusicBuild bash scripts/build-ipa.sh
```

XcodeGen yalnızca `ios/project.yml` değiştikten sonra projeyi yeniden oluşturmak için gerekir. Yerel YouTubeKit paketi `ios/Packages/YouTubeKit` içinde teslim edilir.

## Geliştirme ve testler

Xcode'da **Product → Test** ile birim ve arayüz testlerini çalıştır. Otomatik testler kaynak eşleştirme, söz zamanları, kuyruk, yedekleme, hızlı parça seçimi ve gezinme gibi akışları kapsar. Çevrimiçi testler sağlayıcıların erişilebilir olmasına bağlıdır. Bu teslimatta gerçekten tamamlanan kontroller `VALIDATION-2.9.0.md` içinde kayıtlıdır.

`server/`, `compose.yaml` ve `scripts/run-server.sh` eski sunucu mimarisinin geliştirme araçlarıdır. Release IPA bunları kullanmaz. Yalnızca Debug derlemesinde `-serverURL http://127.0.0.1:8787` başlatma argümanı verilirse geliştirme sunucusu devreye girer.

Görsel söz takibi ve satırdan sarma akışını sağlayıcı bağlantısından bağımsız denemek için `bash scripts/test-ios.sh` çalıştır. Bu komut yerel test verisi sunucusunu açar; birim testlerini, yerel sekme gezinmesini ve zamanlı söz testini çalıştırır. Test bitince test sunucusu kapanır. Bu sunucu yalnızca otomasyon içindir; uygulamanın kullanımı için gerekli değildir. Hedef simülatörü `KLYMUSIC_TEST_DESTINATION` ile değiştirebilirsin.

## Kaynak davranışı

Katalog ve kapaklar Apple'ın herkese açık uç noktalarından; oynatılabilir ses öncelikle YouTube Music eşleştirmesinden (gerekirse aynı kaydı doğrulayan alternatif bağlayıcıdan); sözler LRCLIB'den alınır. Aynı kaydın sanatçı, başlık ve süre eşleşmesi kontrol edilir. Uygun tam kayıt bulunamazsa açık bir hata gösterilir; kısa önizleme tam şarkı gibi sunulmaz. Kaynak erişimi bölgeye ve sağlayıcı değişikliklerine göre farklılık gösterebilir.

Cihazdaki veriler ve ağ istekleri için `PRIVACY.md`; doğrulanan ve cihazda henüz denenmeyen davranışlar için `VALIDATION-2.9.0.md` dosyasına bak.
