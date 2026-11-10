# KlyMusic — tam proje ve devam rehberi

Bu dosya projede ne yapıldığını, uygulamanın nasıl çalıştığını, Mac olmadan nasıl IPA üretildiğini ve yeni sohbette nereden devam edileceğini anlatır. Paket 10 Kasım 2026'da hazırlandı.

## Önce sürüm durumunu oku

| İçerik | Durum |
| --- | --- |
| Bu ZIP'teki kaynak | **2.13.0 / build 20 kaynak adayı** |
| Son doğrulanan iPhone IPA | **2.12.0 / build 19** |
| 2.13.0 iPhone IPA | **Henüz üretilmedi** |
| 2.13.0 yerel kontroller | Linux Swift ile 17 test geçti; 1.200 üretilmiş metadata kontrolü bu testlerin içinde |
| 2.13.0 Xcode/iOS/canlı ses | Çalıştırılamadı; GitHub hesap engeli var |

GitHub'ın Mac işi hiçbir adım başlamadan şu mesajla durdu:

> The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings

Bu mesajın kesin nedeni ödeme veya harcama limiti tarafında hesap sahibi tarafından kontrol edilmeli. Hesapta ücretli limit açılması bu projede otomatik yapılmadı. GitHub erişimi açılmadan yeni sürüm için iPhone derlemesi yapılmış sayılmaz.

Pakette bulunan 2.12.0 IPA, 2.13.0 kaynak kodundan üretilmiş değildir. 2.13.0 genel oynatma düzeltmeleri bu IPA'nın içinde yoktur. Son çalışan IPA ayrıca eklendi ki uygulamanın önceki doğrulanmış sürümü kaybolmasın.

## ZIP'in içindekiler

```text
KlyMusic/
  README.md                         Bu rehber
  DEVAM.md                          Yeni sohbet/geliştirici için görev devri
  iPhone-Kurulum.md                  IPA kurulum açıklaması
  ios/KlyMusic.xcodeproj/            Xcode projesi
  ios/KlyMusic/                      Swift/SwiftUI uygulama kaynakları
  ios/KlyMusicTests/                 Uygulama birim testleri
  ios/KlyMusicUITests/               iPhone simülatörü arayüz testleri
  ios/Packages/YouTubeKit/           Yerel Swift paketi ve kendi testleri
  ios/project.yml                   XcodeGen proje tarifi
  .github/workflows/ios.yml          GitHub Mac derleme/test otomasyonu
  scripts/                          IPA, simülatör, fixture ve taşınabilir test araçları
  artifacts/2.12.0/                  Son doğrulanan imzasız IPA ve SHA256
  screenshots/2.12.0/               39 gerçek simülatör ekranı
  validation/2.12.0/                Başarılı Mac çalışmasının günlükleri
  validation/2.13.0/                Linux test günlükleri, sözdizimi ve GitHub engeli
  Verification-2.13.0.json           Makine tarafından okunabilir mevcut durum
  VALIDATION-2.13.0.md               Hangi kontrollerin çalıştığı/çalışmadığı
  Playback-Notes-2.13.0.md           Son genel oynatma değişiklikleri
  CHANGELOG-COMMITS.txt              Commit adlarıyla değişiklik geçmişi
  PRIVACY.md                        Cihaz verileri ve dış kaynaklar
```

`artifacts`, `screenshots` ve `validation` teslim ZIP'ine eklenir; depodaki derleme çıktıları `dist/` ve `build/` altında tutulur. Önceki sürümlerin doğrulama/araştırma belgeleri de kök klasörde bulunur. `.git` içi, oturum dosyaları, şifre/token, büyük geçici derleme dizinleri ve indirilen Linux Swift toolchain'i bu ZIP'e dahil değildir. Xcode projesi, yerel paket, uygulama varlıkları ve geliştirme/test kaynakları dahildir.

## Uygulama nedir?

KlyMusic, Swift ve SwiftUI ile yazılmış bir iOS müzik uygulamasıdır. Minimum dağıtım hedefi iOS 17.0; son doğrulanan araç Xcode 26.3, cihaz SDK'sı iPhoneOS 26.2'dir. Önceki tam arayüz kontrolleri iPhone 17 Pro / iOS 26 simülatöründe yapıldı. Fiziksel iPhone veya iOS 27 için tam doğrulama iddiası yoktur.

Ana sekmeler Dinle, Keşfet, Kütüphane ve Ara'dır. Uygulamada tam/mini oynatıcı, çalma sırası, karıştır/tekrarla, zamanlı/düz sözler, favoriler, çalma listeleri, geçmiş, indirme, çevrimdışı çalma, tema/dil ve kütüphane yedekleme bulunur. Kullanıcıdan müzik sunucusu adresi, Apple ID veya YouTube çerezi istenmez.

Release uygulaması doğrudan kaynaklara bağlanır. `server/`, `compose.yaml` ve eski sunucu betikleri geliştirme geçmişi içindir; normal Release IPA için çalıştırılmaz. Debug uygulaması yalnızca açık `-serverURL` argümanı verilirse test sunucusunu kullanır.

## İçerikler nereden geliyor?

- **Katalog ve kapaklar:** Apple'ın herkese açık arama/katalog/görsel uçları.
- **Ses:** Önce YouTube Music kaydıyla eşleştirme, uygun video kopyaları ve doğrulanan alternatif JioSaavn kaynağı. Apple'dan tam şarkı sesi alınmıyor.
- **Sözler:** LRCLIB tam kayıt/arama ve Lyrics.ovh düz metin yedeği. Spotify/Musixmatch hesabı veya servisi kullanılmıyor.
- **Cihaz verisi:** SwiftData ile kayıtlar/listeler; ayarlar ve sıra bilgileri yerel tercihlerde; ses ve söz dosyaları uygulama alanında.

Başlık, sanatçı kredileri, sürüm ve gerçek ses süresi kontrol edilir. Kısa önizleme veya başka şarkı, seçilen tam kayıt gibi sunulmaz. Katalogda görünmesi kaynağın çalınabilir tam sesi sunduğu anlamına gelmez. Bölge, kaldırılan kayıt, sağlayıcı değişikliği veya giriş/bot doğrulaması nedeniyle bazı kayıtlar erişilemeyebilir. Bir milyon şarkının hepsinin çaldığı veya internette her parçanın bir saniyede başladığı doğrulanmadı.

## Tasarımda korunması gerekenler

Kullanıcı **oynatıcıyı, native tab bar'ı ve sözlerin akış/animasyon tasarımını onayladı**. Bunları istek olmadan yeniden tasarlamayın.

Kaynak olarak korunan alanlar:

- `ios/KlyMusic/NowPlaying.swift`: tam/mini oynatıcı, söz görünümü/animasyonu, çalma sırası.
- `ios/KlyMusic/KlyMusicApp.swift`: uygulama kökü ve native sekmeler.
- `ios/KlyMusic/Artwork.swift`: kapak ve oynatıcı arka planı.
- `Components.swift` içindeki `TrackMenu` bölümü.

`Protected-UI-Current.json` özetleri ve 2.7.0 tabanıyla karşılaştırma kaydını içerir. SwiftData `SavedTrack` ve `SavedPlaylist` şemaları korunur. Apple Music görsel dili referans alındı; birebir piksel kopyası veya test edilmeyen iOS 27 görünümü diye sunulmaz.

## Bu çalışmalarda ne yapıldı?

| Sürüm/dönem | Yapılan iş |
| --- | --- |
| Önceki temel çalışmalar | SwiftUI uygulama, native sekmeler, tam/mini oynatıcı, kapaktan renklenen oynatıcı arka planı, söz akışı, yerel kütüphane ve indirme |
| 2.7.0 | Oynatıcı menüsü/sıra ve diğer sayfa düzenlemeleri; sonraki çalışmalar için onaylanan arayüz tabanı |
| 2.8.0 | Kütüphane, arama, detaylar ve ayar/veri sayfalarında düzenleme ve gezinme düzeltmeleri |
| 2.9.0 | Düz ayar satırları, raf başlık hizaları, dönüşümlü öneriler, kaydırmaya uyumlu sanatçı başlığı, kalıcı kütüphane kategori düzeni ve eklenme tarihleri |
| 2.10.0 | Yerel şarkı/albüm/sanatçı/liste araması, kategori hata/yeniden deneme durumu, mevcut listelere eklemeli yedek yükleme, tarih/sıralama ve boş kütüphane düzeltmeleri |
| 2.11.0 | Ses kaynaklarını kısa gecikmelerle yarıştırma, ortak istek iptali, sınırlı ses başlığı kontrolü, eksik süre ve Latin/Kiril eşleştirme düzeltmeleri; belirli yazım istisnaları da vardı |
| 2.12.0 | LRCLIB arama + Lyrics.ovh; zamanlı sözü tercih etme; eski/boş/bozuk önbellek ve çevrimdışı söz koruması. Tam Mac doğrulamasında 118 test geçti, 4 canlı ses kontrolü atlandı |
| 2.13.0 kaynak adayı | Şarkı/sanatçı istisna tabloları kaldırıldı; genel metadata motoru, daha çok uygun kopya/sorgu denemesi, ortak medya önbelleği, orijinal ses metadata çözümlemesi ve doğru hata ayrımı. Mac doğrulaması hesap engeli nedeniyle bekliyor |

Her sürümün ayrıntısı kendi `VALIDATION-...md`, `Verification-...json` ve araştırma/not dosyalarında kayıtlıdır. `CHANGELOG-COMMITS.txt` kod kayıt noktalarını listeler.

### 2.13.0'da genel olarak değişenler

`Models.swift` içindeki ortak `RecordingIdentity` artık başlık/sanatçı kimliğini bütün kayıtlarda işler. Unicode/transliterasyon, konuk sanatçıların farklı alanlarda yazılması, ortak krediler, resmi video başlıkları ve sunum etiketleri desteklenir. Remix, Live, Acoustic, hızlandırılmış/yavaşlatılmış sürüm gibi anlamlı ayrımlar korunur. Genel algoritmada şarkı veya sanatçı adına özel bir liste yoktur.

İlk üç kopya başarısız olduğunda işlem bırakılmaz. Sorgu başına en fazla sekiz geçerli aday, aynı anda en fazla iki ses denemesi ve en fazla dört genel sorgu denenebilir; tekrar eden kimlikler aynı aşamada elenir. Aynı medya kimliği/kalite/süre için ortak istek ve önbellek kullanılır; oynatma başarısızlığında URL yenilenebilir.

YouTube'un `English (Original)` gibi parantezli veya yerelleştirilmiş orijinal ses etiketi önce yanlış elenebiliyordu. Filtre ve isteğe bağlı metadata alanı düzeltildi. Varsayılan işaretin otomatik dublaj da olabileceği dikkate alınır; belirsiz alternatifler rastgele orijinal diye kabul edilmez.

“Eşleşen kayıt yok”, “kaynak sunamıyor”, “ses bağlantısı doğrulanamadı”, “ağ hatası” ve “giriş doğrulaması” artık aynı hata değildir. Bu, sağlayıcı erişim engelini uygulamadaki isim eşleştirme hatası diye göstermemek içindir. Giriş engelini aşan bir yöntem eklenmedi.

## Kaynak dosyaları nerede?

| Dosya/klasör | Görevi |
| --- | --- |
| `KlyMusicApp.swift` | Uygulama başlangıcı, bağımlılıklar ve native sekmeler |
| `NowPlaying.swift` | Onaylanan oynatıcı, söz görünümü/animasyonu ve sıra |
| `Player.swift` | AVQueuePlayer, ses oturumu, sıra/ön hazırlık, söz yükleme ve söz önbelleği |
| `NativeCatalog.swift` | Katalog, arama, kaynak eşleştirme, akış ve söz sağlayıcıları |
| `Models.swift` | Veri tipleri, genel kayıt kimliği ve SwiftData modelleri |
| `API.swift` | İstek arayüzü, ortak istekler, medya/eşleştirme önbelleği ve hata tipleri |
| `Downloads.swift` | Arka plan indirme, dosya doğrulama ve sınırlı ses başlığı kontrolü |
| `Browse.swift` | Ana sayfa, keşfet, arama, albüm ve sanatçı sayfaları |
| `Library.swift`, `LibraryViews.swift` | Yerel kütüphane, listeler, yedek/geri yükleme ve kütüphane ekranları |
| `Settings.swift`, `Localization.swift` | Tercihler, dil/yerel ayar ve ayar ekranları |
| `Artwork.swift` | Kapak önbelleği ve oynatıcı renkleri |
| `ios/Packages/YouTubeKit` | Kullanılan yerel çıkarıcı, parser/decoder ve paket testleri |

## Mac olmadan iOS uygulamasını nasıl yaptık?

Kaynaklar Linux çalışma alanında düzenlendi. iOS uygulamasını Linux'ta Xcode ile derlemedik ve Linux içine sanal macOS kurmadık. GitHub Actions, kendi altyapısında geçici bir Mac ayırdı; Xcode derlemesi ve iPhone simülatörü orada çalıştı.

Depo: **https://github.com/KlyMorias0/KlyMusic** — özel depo.

Akış şöyledir:

1. Kod GitHub'a commit/push ile kaydedilir.
2. `.github/workflows/ios.yml`, Actions sayfasından elle `workflow_dispatch` ile başlatılır.
3. `macos-15` makinesi açılır; `/Applications/Xcode_26.3.app/Contents/Developer` seçilir.
4. Depo indirilir. Yerel YouTubeKit paketi proje bağımlılığı olarak derlenir.
5. `bash scripts/build-ipa.sh`, Release iPhoneOS ARM64 `.app` üretir. Kod imzalama kapalıdır.
6. Uygulama `Payload/KlyMusic.app` olarak ZIP'lenip `.ipa` adıyla kaydedilir.
7. `bash scripts/ci-verify.sh`, yerel test verisi sunucusu ve simülatörle birim/arayüz testlerini çalıştırır. Paket testleri de çalışır.
8. IPA, SHA256, günlükler ve ekran görüntüleri GitHub Releases'e kaydedilir. Sonuçlar incelenir; kaynak/raporlarla teslim edilir.
9. İş bitince geçici Mac ortamı temizlenir. Kalıcı kalanlar depoya veya release'e kaydedilen dosyalardır.

GitHub Actions'ın ücretsiz kullanım hakkı hesap planı/kotasına bağlıdır; özel depoda sınırsız Mac hakkı değildir. Son çalışmada GitHub ödeme/harcama limiti engeli bildirdi. Bu yüzden 2.13.0 için iş hiç başlamadı. Testleri atlamak bu hesap engelini çözmez.

## GitHub'dan yeniden IPA üretme

Hesap engeli giderildikten ve özel depoya erişim sağlandıktan sonra:

1. Depoyu aç → **Actions**.
2. **Build and verify KlyMusic** akışını seç.
3. **Run workflow** → `main` → çalıştır.
4. Yalnızca “Build” değil, test ve sonuç yükleme adımlarının da durumunu kontrol et.
5. Başarılı son çalışmanın dosyalarını **Releases** bölümünden indir.
6. Sürüm/build, SHA256, cihaz platformu ve test raporlarının aynı koda ait olduğunu doğrula.

Yetkili GitHub CLI ile eşdeğer komut:

```sh
gh workflow run ios.yml --ref main
gh run list --workflow ios.yml --limit 5
gh run watch RUN_ID --exit-status
```

GitHub hesabı için OAuth/`gh auth login` gibi yetkilendirme kullanılır. Parolayı sohbet veya kaynak dosyasına yazmak gerekmez. Workflow içindeki `github.token`, GitHub'ın o işe verdiği otomatik erişimdir; kullanıcı parolası değildir. Yeni sohbet mevcut çalışma alanının GitHub oturumunu otomatik devralmayabilir.

## Mac/Xcode varsa yerelde derleme

`ios/KlyMusic.xcodeproj` dosyasını **Xcode 26.3** ile aç, `KlyMusic` şemasını seç. Simülatörde çalıştırmak için gerçek müzik sunucusu kurman gerekmez. Mevcut bazı native arayüz API'leri nedeniyle Xcode 26.0 yerine kullanılan 26.3 sürümü esas alınmalı.

Terminalden IPA:

```sh
KLYMUSIC_BUILD_DIR=/tmp/KlyMusicBuild bash scripts/build-ipa.sh
```

Çıktı `dist/KlyMusic-unsigned.ipa` ve `dist/SHA256.txt` olur. Gerçek cihaza doğrudan Xcode ile kurmak için kendi geliştirme takımını/imzalama ayarlarını seçmek gerekir. `ios/project.yml` değişirse XcodeGen ile proje yeniden üretilebilir; teslimatta `.xcodeproj` zaten bulunur.

## IPA nasıl telefona yüklenir?

Paketteki kurulabilir dosya `artifacts/2.12.0/KlyMusic-2.12.0-unsigned.ipa` yolundadır. Repo içinden yeni derleme alındığında çıktı `dist/` altında olur.

IPA imzasızdır. Kullandığın sideload aracıyla kendi Apple hesabın/sertifikan üzerinden imzala ve yükle; gerektiğinde aracın istediği geliştirici güveni veya Geliştirici Modu işlemlerini tamamla. KlyMusic içine Apple ID/parola girilmez. Bu paket App Store/TestFlight yayını değildir. İmzalama aracının hesap/sertifika sınırları ayrıca geçerlidir.

## Testleri nasıl çalıştırırız?

Mac'te tam uygulama kontrolü:

```sh
bash scripts/ci-verify.sh
swift test --package-path ios/Packages/YouTubeKit --filter 'ParserTests|ExtractionTests|FastAudioTests'
```

`ci-verify.sh` test için `127.0.0.1:8879` üzerinde fixture sunucusu açar, simülatör hazırlar ve test bitince sunucuyu kapatır. Bu test servisi normal Release uygulamasında kullanılmaz. Ekran görüntülerindeki bazı şarkı adları/sözler test verisidir; gerçek katalog veya canlı ses başarısı kanıtı değildir.

2.13.0 kaynak adayındaki Linux kontrolleri:

```sh
python3 scripts/test-recording-identity-portable.py --swiftc /path/to/swiftc
python3 scripts/test-audio-metadata-portable.py --swiftc /path/to/swiftc
python3 scripts/test-resolver-portable.py --swiftc /path/to/swiftc
```

Bu betikler üretim kodunu ve gerçek XCTest yöntemlerini alır. Kimlikte 5, ses metadata/hata sınıfında 7, enjekte edilmiş HTTP/sesle çözümleyicide 5 test geçti. Çözümleyici testlerinde gerçek CDN çıkarımı yapılmaz; kullanılmayan platform yolları açık test adaptörleriyle ayrılır. Bunlar tam iOS uygulaması, AVPlayer veya gerçek YouTube çalma testi yerine geçmez.

**Son tam doğrulama 2.12.0:** 92 uygulama testi + 5 arayüz testi + 21 paket testi = 118 başarılı; sağlayıcı erişimi nedeniyle 4 canlı ses tanılaması atlandı. Canlı söz kontrolünde Tarkan/Şımarık için zamanlı söz alındı.

**2.13.0 planlanan Mac kapsamı:** 107 uygulama testi, 5 seçilmiş arayüz testi ve 28 paket testi. Bu sayılar iOS'ta henüz tamamlanmış sonuçlar değildir. `Verification-2.13.0.json` ve `VALIDATION-2.13.0.md` mevcut engeli ve gerçek kısmi sonuçları kaydeder.

## Yeni sohbette devam edecek kişiye

Önce `DEVAM.md`, `VALIDATION-2.13.0.md`, `Verification-2.13.0.json` ve `Protected-UI-Current.json` okunmalı. Son kullanıcı isteği tek tek şarkı yaması değil, bütün kayıtlara uygulanan ortak oynatma sisteminin düzeltilmesidir. Şarkı/sanatçı adlarına özel yeni istisna tablosu eklenmemeli.

Kalan ana iş: GitHub hesap engeli kaldırıldıktan sonra kaynakların tamamını Xcode'da derlemek, testlerde çıkabilecek sorunları çözmek, farklı gerçek kayıtlarla eşleşme/çalma sonuçlarını ayrı ölçmek ve ancak ardından yeni IPA teslim etmek. Eski IPA'yı yeni kaynaklardan üretilmiş gibi sunmayın. Kaynak engelini “başka şarkı çalarak” veya doğrulamayı kaldırarak gizlemeyin.

Yeni sohbete bu ZIP'i eklemek yeterlidir; inceleme için GitHub şifresi gerekmez. Özel depoya push/Actions için ayrıca yetkili GitHub bağlantısı gerekir.
