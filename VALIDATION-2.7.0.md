# KlyMusic 2.7.0 (14) — 8 Kasım 2026

[Son CI çalışması](https://github.com/KlyMorias0/KlyMusic/actions/runs/42474525071) başarılı.
Kod: `6809d7ffbe1e67f3c0905c33d59843452b14cca1`.

- Release iPhoneOS ARM64 cihaz derlemesi geçti. iOS 17.0+, SDK iphoneos26.2, Xcode 26.3. Paket imzasızdır.
- 53 uygulama birim testi, 5 arayüz testi ve 15 YouTubeKit testi geçti: toplam **73 başarılı test, 0 hata**. Üç canlı sağlayıcı tanılaması çalınabilir ses alınamadığı için atlandı.
- Tüm NowPlaying.swift (tam/mini oynatıcı, sıra, sözler), native tab/root, Artwork.swift ve oynatıcının TrackMenu bileşeni 2.6.0 ile kaynak düzeyinde birebir aynıdır. Protected-UI-Current.json kapsam ve hash değerlerini içerir.
- Kütüphane kategori satırları, ayrı liste oluşturma/seçme sayfaları, albüm/sanatçı detayları, kategori/sonuç araması ve ayar Form'u yeniden kuruldu. Arayüz testleri liste oluşturmayı, albüm/sanatçı filtreleri ve detaylarını, kalite alt sayfasında seçimi, menü ve sırayı doğruladı.
- Native tab bar açık/koyu temada, söz takibi ve satırdan sarma, sözlere geçince oynatıcı kontrol boyut/konumunun korunması testleri geçti. Yeni sayfaların test görüntüleri incelendi.
- Gerçek yayımlanmış mashup/medley kaydının engellenmemesi, konuk sanatçı bilgisinin alanlar arasında taşınması ve “Sevil Sevinc & Dj Roshka - Azeri Mashup 2” gibi açık kredili ortak sanatçı yüklemesinin eşleştirilmesi test edildi. İlgisiz yükleyici, farklı sanatçı, remix ve çift uzunlukta dosya reddedilir.
- YouTube ses formatındaki approxDurationMs artık Stream üzerinde taşınır. URL'de dur alanı yoksa format süresi kullanılabilir; geçersiz ve çelişen süreler reddedilir. SDK format çözümleme testi geçti.
- Ortak oynatıcı kodu önbelleğinin eşzamanlı çağrıları birleştirmesi, geçersizleştirme ve başarısız isteğin sonraki parçayı bozmaması testleri geçti. Görünen ilk üç parçanın eşleştirmesi ses indirmeden hazırlanır; aynı eşleştirme isteği paylaşılır.
- IPA ZIP bütünlüğü, SHA256, sürüm/build, iPhoneOS platformu, ARM64 Mach-O ve imzasız paket yapısı doğrulandı. Test/kategori görselleri uygulama paketine dahil değildir.

## Canlı ses ve bir saniye hedefi

“Azeri Mashup 2”, “Say It Right” ve Tarkan tanılamalarında bu CI bağlantısından çalınabilir akış alınamadı. YouTube istemcileri LOGIN_REQUIRED / “Sign in to confirm you’re not a bot” yanıtı verdi. Kayıt eşleştirmesi ile ses bağlantısına erişim ayrı aşamalardır; eşleşme bir şarkının burada çalındığını kanıtlamaz.

**Bir saniyede duyulabilir başlangıç ve tüm katalog kayıtlarının çalması doğrulanmadı.** Bu sürüm bunları garanti etmez. UI testleri yerel ses/metadata kullanır; ekran görüntüleri canlı YouTube çalmasını veya gerçek iPhone gecikmesini kanıtlamaz. Ayrıntılı tanılama Verification-2.7.0.json ve release verification.log içindedir.

Fiziksel iPhone testi, gerçek mobil veri tüketimi ve iOS 27 runtime testi yapılmadı. Arayüz iPhone 17 Pro / iOS 26 simülatöründe doğrulandı. iOS 27 tasarım kaynakları Design-Research-2.7.0.md içindedir.

IPA SHA256: `59dee32bdd6946ab90c68e06ad95b516386483be87115a5e7ad89e69e2c94a51`.

Önceki sürüm belgeleri tarihsel kayıttır; güncel sonuç bu belgedir.
