# KlyMusic 2.10.0 (17) — 8 Kasım 2026

[CI çalışması](https://github.com/KlyMorias0/KlyMusic/actions/runs/42526808660) başarılı. Kod: `ecc56370edc4d337b54a8734054f08eea58f32c8`.

- Release iPhoneOS ARM64 derlemesi geçti; iOS 17.0+, SDK iphoneos26.2, Xcode 26.3. IPA imzasızdır.
- 68 uygulama birim testi, 5 arayüz testi ve 15 YouTubeKit testi geçti: **88 başarılı, 3 atlanan, 0 başarısız test**.
- Yeni regresyonlar yerel aramada sözcüklerin farklı sırayla eşleşmesini, aynı albüm adının farklı sanatçılarda ayrılmasını, sanatçı ortak çalışmalarının aynı kimlikte birleşmesini, liste aramasını ve boş sorguyu doğruladı.
- Yedek testleri mevcut listeye eksik şarkıların eklenmesini, yerel ad/sıranın korunmasını, yinelenen içe aktarmaların çoğalmamasını, gerçek/tahmini tarih birleştirmesini ve kategori düzeni/sıralama tercihlerinin taşınmasını kapsadı.
- Arayüz testi yeni liste oluşturup Kitaplığın kapsamında buldu ve yerel listeyi açtı. Katalog araması, albüm/sanatçı sayfaları ve önceki kategori düzenleme akışları tekrar doğrulandı.
- Ayarlarda kalite seçimi, tema/dil alt sayfalarının seçenekleri ve mevcut seçim işaretleri, veri alt sayfası, geçmiş temizleme onayı ve Hakkında gezinmesi test edildi. Açıklamalar küçük ikincil metne dönüştürüldü.
- Onaylanan oynatıcı/mini oynatıcı, söz takibi/satırdan sarma, native tab gezinmesi, oynatıcı parça menüsü ve sıra testleri geçti. NowPlaying.swift, KlyMusicApp.swift, Artwork.swift ve TrackMenu kaynakları 2.7.0 tabanıyla birebir aynı. SwiftData SavedTrack/SavedPlaylist şeması da değişmedi.
- Testten çıkan gerçek PNG ekranları incelendi. Ekranlar yerel test metadata/sesini kullanır; canlı katalog veya gerçek iPhone ölçümü değildir. Kaydırma sırasında üst başlık davranışı simülatörde doğrulandı.
- IPA ZIP bütünlüğü, sürüm/build, SHA256, iPhoneOS platformu, ARM64 çalıştırılabilir ve imzasız paket yapısı doğrulandı; fixture görseller/sesler uygulama paketinde yoktur.

## Sınırlar

3 canlı ses tanılaması çalınabilir akış alınamadığı için atlandı. Bir saniyede duyulabilir başlangıç, tüm katalog kayıtlarının çalması ve gerçek mobil veri tüketimi doğrulanmadı. Bu sürüm ses çözümleme hattını değiştirmez. Fiziksel iPhone, iOS 27 ve Apple Music ile piksel eşitliği denenmedi.

Eski kayıtların gerçek eklenme tarihi yoktur. Önceki sıralama ve son dinleme verisinden bir kez tahmini tarih atanır; bu tarih geçmişteki gerçek eklenme zamanı diye sunulmaz. Yeni kayıt/liste tarihleri saklanır ve yeni yedeklerle taşınır. Eski yedekler desteklenir. Öneriler dinleme sanatçılarına dayanır; ilişkili sanatçı keşif motoru değildir.

IPA SHA256: `d0ab8e0e89a74be81b6cdc327f977ba2c7b4d5ff2e80d3545bc04dee565788b0`.
