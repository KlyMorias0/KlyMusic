# KlyMusic — mevcut görev devri, 10 Kasım 2026

Ana rehber README.md'dir. Bu dosya yeni sohbette doğrudan devam etmek içindir.

## Mevcut durum

- Depo: https://github.com/KlyMorias0/KlyMusic — özel.
- Kaynak: 2.13.0 / build 20, genel oynatma sistemi güncellemesi.
- Son gerçek iPhone IPA: 2.12.0 / build 19. 2.13.0 kodunu içermez.
- 2.13.0 Mac işi: https://github.com/KlyMorias0/KlyMusic/actions/runs/42775580626
- İş hiçbir adım başlamadan GitHub ödeme/harcama limiti engeliyle durdu. Bu bir kod test başarısızlığı değildir; yeni iOS derlemesi yapılmadı.
- Linux'ta resmî Swift 6.0.3 ile 17 gerçek XCTest yöntemi geçti. 5 kimlik testi içinde 12 dilde 1.200 üretilmiş metadata kontrolü var. Bu sayı gerçek şarkı çalma testi değildir.
- Kontrollerin ayrıntısı VALIDATION-2.13.0.md / Verification-2.13.0.json içindedir.

## Kullanıcının son isteği ve sınırları

Kullanıcı, yalnızca Sigma Boy gibi tek tek şarkılara yama yapılmasını istemiyor. Ortak eşleştirme/oynatma mekanizmasının bütün katalog kayıtlarına uygulanmasını istiyor. Genel kurallar düzeltildi; isim tablosu yaklaşımı kaldırıldı. Tüm şarkıların veya bir saniyelik duyulabilir açılışın doğrulandığını söyleme.

Oynatıcı, native tab bar ve söz akışı/animasyonu onaylıdır. NowPlaying.swift, KlyMusicApp.swift, Artwork.swift ve TrackMenu korunmalı. SavedTrack/SavedPlaylist şemalarını gereksiz değiştirme. Protected-UI-Current.json 2.7.0 tabanını ve özetleri kaydeder.

2.12.0 çok kaynaklı sözler ve önbellek düzeltmeleri korunur. LRCLIB ve Lyrics.ovh kullanılır; Spotify söz sağlayıcısı kullanılmaz.

## Son kod değişiklikleri

Models.swift: RecordingIdentity; tam başlık/sürüm/kredi karşılaştırması, genel Unicode/transliterasyon, feat bilgisinin farklı yerde olması, desteklenen sunum etiketleri ve güvenli sanatçı ayracı kuralları. Şarkı/sanatçı adı tablosu yok.

NativeCatalog.swift: aynı kaydın sekize kadar aday kopyasını ve dörde kadar genel sorguyu deneme; ilk eşleşen kopyalar başarısızsa sonraki sorguya geçme; aynı medya için ortak stream önbelleği; metadata parser'ında UC artist/işaretsiz kredi desteği. Audio API önbellekleri oynatma hatasında yenilenebilir.

YouTubeKit: Original etiketinin parantez/yerel dil biçimleri ve eksik audioIsDefault alanı; tüm alternatifler başarısız olunca bilinen giriş/erişim durumunu koruma. Giriş doğrulaması aşma mekanizması eklenmedi.

API.swift: eşleşme yok / kaynak erişimi / medya / ağ / giriş hatası ayrımı; bir yedek boş diye daha açıklayıcı kaynak hatası kaybolmaz.

Yeni Linux betikleri gerçek kaynak parçalarını ve testleri çıkarır; resolver'da HTTP/ses enjekte edilir. Tam Apple SDK derlemesi veya gerçek CDN çıkarımı değildir.

## Kalan iş

1. Hesap sahibi GitHub Settings → Billing & plans engelini kontrol etmeli. Ücretli limit/ödeme işlemini kendiliğinden değiştirme.
2. Ardından `.github/workflows/ios.yml`, main üzerinden çalıştırılmalı. Xcode 26.3 / macos-15.
3. Gerçek iPhoneOS Release derlemesi, 107 uygulama testi, 5 seçili UI testi, 28 paket testi ve canlı tanılamalar incelenmeli.
4. Kod veya test hatası çıkarsa ortak mekanizmada düzelt; yeni şarkı ismi istisnası yazma.
5. Son başarılı çalışmanın IPA/rapor/SHA256 dosyaları eşleştirilmeli; ekranlar incelenmeli. Sonra yeni sürüm teslim edilmeli.

Komutlar README.md'de var. Bu ZIP'te parola/token veya mevcut sohbetin GitHub oturumu yoktur. Yeni ortamda özel depoya erişim OAuth/CLI/bağlantı üzerinden ayrıca yetkilendirilir.
