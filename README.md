# KlyMusic 2.11.0 (18)

KlyMusic, iOS 17 ve sonrası için SwiftUI ile geliştirilmiş bir müzik uygulamasıdır. Katalog, arama, ses bağlantısı çözümleme ve şarkı sözleri doğrudan telefonda çalışır. Kullanıcı hesabı veya müzik sunucusu adresi girmen gerekmez. Favoriler, çalma listeleri ve indirilen şarkılar cihazda saklanır.

## iPhone'a kurulum

`dist/KlyMusic-unsigned.ipa`, ARM64 iPhone/iPad Release paketidir. İmzasızdır; yüklemeden önce kullandığın sideload aracıyla kendi Apple hesabın üzerinden imzalaman gerekir. Apple ID, parola veya sertifikanı KlyMusic'e girmezsin.

Uygulamayı açınca **Dinle**, **Keşfet**, **Kütüphane** ve **Ara** sekmelerini kullanabilirsin. Yeni liste oluşturmak için **Kütüphane → … → Yeni Çalma Listesi…** yolunu izle. Bir şarkı seçildiğinde mini oynatıcı açılır. Mini oynatıcıya dokunarak tam oynatıcıya, sözlere ve çalma sırasına geçebilirsin. İndirilen şarkılar **Kütüphane → İndirilenler** içinde internet olmadan oynatılır.

## Bu sürüm — 2.11.0

- **Kayıt eşleştirme:** Sigma Boy (Сигма Бой) gibi aynı başlığın Latin/Kiril yazımı eşleşebilir. İki dildeki parantezli başlık ancak transliterasyonları aynıysa ayrılır; remix/live/sped-up sürüm işaretleri korunur. Bildirilen sanatçıların açık alternatif yazımları desteklenir; eksik veya başka sanatçı kredileri kabul edilmez.
- **Kaynak beklemesi:** YouTube şarkı araması hemen, video araması 450 ms, alternatif kaynak 900 ms sonra başlayabilir. Doğrulanan ilk bağlantı kullanılır; önceki kaynağın tamamen hata vermesi beklenmez. Daha önce kaydedilmiş eşleşme de yedekleri süresiz bekletmez. Bu süreler sesin başlayacağı zaman veya üst sınır değildir.
- **İptal ve önbellek:** Ortak arama/oynatıcı bağlamı isteklerinde her dinleyici ayrı iptal olabilir. Bir kaynak kazandığında kaybeden bekleyiciler serbest bırakılır; başka bir işlem aynı isteği kullanıyorsa o işlem devam eder. Eski yanıt yeni bağlamı ezmez.
- **Az veri:** Bağlantı doğrulaması yalnızca kapsayıcı başlığını saklar ve aktarımı iptal eder. Sunucu Range isteğini yok sayarsa tam dosya belleğe alınmaz. Bu, toplam uygulama trafiğinin 12 bayt olduğu veya ölçülmüş veri tasarrufu yüzdesi anlamına gelmez. Düşük bit hızı ve ses ön yükleme tercihleri korunur; yavaş kaynakta yarışan metadata istekleri ek trafik oluşturabilir.
- **Eksik süre:** Video aramasında süre bulunmayan, kimliği doğru adaylar istenen süre biliniyorsa gerçek akış süresiyle doğrulanabilir. Doğrudan YouTube kaydının süresi de gerçek medyadan öğrenilebilir. Farklı süreli birleşik/yanlış kayıt reddi korunur.
- **Çıkarıcı yedeği:** Hızlı oynatıcı bağlamının geçici hatası tam çıkarıcıyı atlamaz. Kullanıcının iptali yeni bir çıkarım isteği açmaz.
- **Onaylanan arayüz korunmuştur:** Oynatıcı, mini oynatıcı, sözler, native tab bar, çalma sırası, oynatıcı menüsü ve kapak/arka plan kaynakları 2.7.0 tabanıyla aynıdır. Kütüphane/arama/ayar sayfalarının 2.10.0 davranışları da korunur. SwiftData şeması değişmedi.

Bu sürüm ses eşleştirme ve çözümleme hattını değiştirir. Bir saniyede duyulabilir başlangıç veya tüm katalog kayıtlarının çalması garantisi verilmez. Sağlayıcı erişimi ağ/bölge koşullarına bağlıdır. Apple Music görsel dili referans alınır; iOS 27 veya fiziksel cihazda piksel eşitliği doğrulanmış değildir.

Ses tüketimi kaynak bit hızına bağlıdır. Örneğin 48 kbps AAC yaklaşık 21,6 MB/saat, 128 kbps yaklaşık 57,6 MB/saat ses verisidir; bunlar ölçülmüş toplam uygulama trafiği veya üst sınır değildir. Kapak, arama ve protokol trafiği ayrıca oluşur. Veri tercihi indirmelerde ve yedek/geri yüklemede de korunur.

Güncel doğrulama `VALIDATION-2.11.0.md` içinde kaydedilir. Önceki doğrulama belgeleri önceki sürümlere aittir.

## Xcode ile çalıştırma

Test edilen araç sürümü **Xcode 26.3**. Bu sürümle `ios/KlyMusic.xcodeproj` dosyasını açıp **KlyMusic** şemasını seç. Kullanılan `tabViewBottomAccessory(isEnabled:)` API’si Xcode 26.0 SDK’sında bulunmadığından derleme için Xcode 26.3 kullan. Simülatör doğrudan müzik kaynaklarına bağlanır; Python sunucusu başlatman gerekmez. Gerçek cihaza Xcode üzerinden yüklemek için kendi imzalama takımını seç ve cihaz yapılandırmasında `CODE_SIGNING_ALLOWED` ayarını `YES` yap. Teslim edilen IPA, sideload için imzasız üretilir.

Cihaz IPA'sını yeniden üretmek için:

```sh
KLYMUSIC_BUILD_DIR=/tmp/KlyMusicBuild bash scripts/build-ipa.sh
```

XcodeGen yalnızca `ios/project.yml` değiştikten sonra projeyi yeniden oluşturmak için gerekir. Yerel YouTubeKit paketi `ios/Packages/YouTubeKit` içinde teslim edilir.

## Geliştirme ve testler

Xcode'da **Product → Test** ile birim ve arayüz testlerini çalıştır. Otomatik testler kaynak eşleştirme, söz zamanları, kuyruk, yedekleme, hızlı parça seçimi ve gezinme gibi akışları kapsar. Çevrimiçi testler sağlayıcıların erişilebilir olmasına bağlıdır. Bu teslimatta gerçekten tamamlanan kontroller `VALIDATION-2.11.0.md` içinde kayıtlıdır.

`server/`, `compose.yaml` ve `scripts/run-server.sh` eski sunucu mimarisinin geliştirme araçlarıdır. Release IPA bunları kullanmaz. Yalnızca Debug derlemesinde `-serverURL http://127.0.0.1:8787` başlatma argümanı verilirse geliştirme sunucusu devreye girer.

Görsel söz takibi ve satırdan sarma akışını sağlayıcı bağlantısından bağımsız denemek için `bash scripts/test-ios.sh` çalıştır. Bu komut yerel test verisi sunucusunu açar; birim testlerini, yerel sekme gezinmesini ve zamanlı söz testini çalıştırır. Test bitince test sunucusu kapanır. Bu sunucu yalnızca otomasyon içindir; uygulamanın kullanımı için gerekli değildir. Hedef simülatörü `KLYMUSIC_TEST_DESTINATION` ile değiştirebilirsin.

## Kaynak davranışı

Katalog ve kapaklar Apple'ın herkese açık uç noktalarından; oynatılabilir ses öncelikle YouTube Music eşleştirmesinden (gerekirse aynı kaydı doğrulayan alternatif bağlayıcıdan); sözler LRCLIB'den alınır. Aynı kaydın sanatçı, başlık ve süre eşleşmesi kontrol edilir. Uygun tam kayıt bulunamazsa açık bir hata gösterilir; kısa önizleme tam şarkı gibi sunulmaz. Kaynak erişimi bölgeye ve sağlayıcı değişikliklerine göre farklılık gösterebilir.

Cihazdaki veriler ve ağ istekleri için `PRIVACY.md`; doğrulanan ve cihazda henüz denenmeyen davranışlar için `VALIDATION-2.11.0.md` dosyasına bak.
