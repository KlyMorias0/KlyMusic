# KlyMusic 2.9.0 (16) — 8 Kasım 2026

[CI çalışması](https://github.com/KlyMorias0/KlyMusic/actions/runs/42496643422) başarılı. Kod: `1bf5afa7719c0f3076ca23ab48986e6679b32e2f`.

- Release iPhoneOS ARM64 derlemesi geçti; iOS 17.0+, SDK iphoneos26.2, Xcode 26.3. IPA imzasızdır.
- 61 uygulama birim testi, 5 arayüz testi ve 15 YouTubeKit testi geçti: **81 başarılı, 3 atlanan, 0 başarısız test**.
- Yeni regresyonlar albüm/liste karışık tarih sırasını, albüm tekilleştirmeyi, tekrar dinlemenin sırayı değiştirmemesini, yeniden açılış ve yedekten geri yüklemede tarihlerin korunmasını doğruladı. Eski tarih başlangıcı bir kez yapılır; kategori düzeni/gizleme, bozuk/tekrarlanan düzeni onarma ve farklı uzunluktaki öneri raflarını dönüşümlü birleştirme test edildi.
- Arayüz testinde kategori gizlendi, uygulama yeniden açıldı ve tercihin kaldığı doğrulandı; kategori geri açıldı. Başlık sıralaması ve varsayılan sıraya dönüş, liste oluşturma, arama filtreleri ve sanatçı sayfası doğrulandı. Büyük sanatçı adı görünürken üst başlığın tekrarlanmadığı, kaydırılınca üst başlığın geldiği test edildi.
- Düz ayar listesi açık/koyu temada görüntülendi; kalite seçimi, veri alt sayfası, geçmiş temizleme onayı ve Hakkında gezinmesi geçti.
- Onaylanan oynatıcı/mini oynatıcı, söz takibi/satırdan sarma, native tab gezinmesi, oynatıcı parça menüsü ve sıra testleri geçti. NowPlaying.swift, KlyMusicApp.swift, Artwork.swift ve TrackMenu kaynakları 2.7.0 tabanıyla birebir aynı. SwiftData SavedTrack/SavedPlaylist şeması da değişmedi.
- Testten çıkan gerçek PNG ekranları incelendi. Ekranlar yerel test metadata/sesini kullanır; canlı katalog veya gerçek iPhone ölçümü değildir. Kaydırma sırasında üst başlık davranışı simülatörde doğrulandı.
- IPA ZIP bütünlüğü, sürüm/build, SHA256, iPhoneOS platformu, ARM64 çalıştırılabilir ve imzasız paket yapısı doğrulandı; fixture görseller/sesler uygulama paketinde yoktur.

## Sınırlar

3 canlı ses tanılaması çalınabilir akış alınamadığı için atlandı. Bir saniyede duyulabilir başlangıç, tüm katalog kayıtlarının çalması ve gerçek mobil veri tüketimi doğrulanmadı. Bu sürüm ses çözümleme hattını değiştirmez. Fiziksel iPhone, iOS 27 ve Apple Music ile piksel eşitliği denenmedi.

Eski kayıtların gerçek eklenme tarihi yoktur. Önceki sıralama ve son dinleme verisinden bir kez tahmini tarih atanır; bu tarih geçmişteki gerçek eklenme zamanı diye sunulmaz. Yeni kayıt/liste tarihleri saklanır ve yeni yedeklerle taşınır. Eski yedekler desteklenir. Öneriler dinleme sanatçılarına dayanır; ilişkili sanatçı keşif motoru değildir.

IPA SHA256: `df6c92f2e3df298f131dc506262b75c5b8f6c75cc207b90c4f9e92c97e50ebe5`.
