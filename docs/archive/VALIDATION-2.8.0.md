# KlyMusic 2.8.0 (15) — 8 Kasım 2026

[Son CI çalışması](https://github.com/KlyMorias0/KlyMusic/actions/runs/42479879904) başarılı. Kod: `fb7bbde7a2921f5cad37ae435575dd7c5f895b13`.

- Release iPhoneOS ARM64 cihaz derlemesi geçti; iOS 17.0+, SDK iphoneos26.2, Xcode 26.3. Paket imzasızdır.
- 57 uygulama birim testi, 5 arayüz testi ve 15 YouTubeKit testi geçti: toplam **77 başarılı test, 0 hata**. 3 canlı ses tanılaması çalınabilir akış alınamadığı için atlandı.
- Tam ve mini oynatıcı, sıra, şarkı sözleri, native tab/root, Artwork.swift ve TrackMenu 2.7.0 ile kaynak düzeyinde birebir aynıdır. Ayrıntılar Protected-UI-Current.json içindedir.
- Yeni regresyon testleri, ana sayfa raflarında aynı kaydın yeniden basımlarını eleme ve remixleri koruma; desteklenen editoryal kategori verisini çözme; Son Eklenenler sırasını yeniden açınca/tekrar dinleyince koruma; eski sanatçı yanıtlarını tarih uydurmadan çözme davranışlarını doğruladı.
- Arayüz testleri kategori/sonuç aramasını, albüm/sanatçı filtrelerini ve yeni yayın kartını, liste oluşturmayı, kalite seçimini, Kütüphane ve Veriler/Hakkında alt sayfalarını ve geçmiş temizleme onayını doğruladı.
- Gerçek dinleme sonrası Senin için rafının ve ayrı Son dinlenenler alanının görünmesi doğrulandı. Native tab bar açık/koyu temada, söz takibi/satırdan sarma ve kontrol konumunun korunması, oynatıcı menüsü ve sıra testleri geçti.
- Yeni sayfaların gerçek test ekran görüntüleri incelendi. Editoryal kategori görselleri sr dikdörtgen kırpmasıyla istenir; yüzleri kesen cc kare kırpması kaldırıldı. Albüm kapakları sanatçı portresi olarak kullanılmaz.
- IPA ZIP bütünlüğü, SHA256, sürüm/build, iPhoneOS platformu, ARM64 Mach-O ve imzasız paket yapısı doğrulandı. Fixture ses/görseller uygulama paketinde yoktur.

## Sınırlar

Canlı YouTube kaynaklarına erişim bu CI bağlantısında doğrulanamadı. **Bir saniyede duyulabilir başlangıç ve tüm katalog kayıtlarının çalması doğrulanmadı.** Önceki eşleştirme, ön hazırlık ve az veri davranışları korunur; öneriler yüklendikten sonra yeni görünen parçalar hazırlanır. UI testleri yerel ses kullanır; canlı akış gecikmesini veya mobil veri tüketimini ölçmez.

Fiziksel iPhone, iOS 27 runtime testi ve Apple Music ile fiziksel cihazda piksel eşitliği doğrulaması yapılmadı. Tasarım referansları Design-Research-2.8.0.md içindedir. Eski veri tabanlarında eklenme tarihi bulunmadığından kütüphane sırası mevcut veriden bir kez başlatılır; sonraki yeni kayıtların eklenme sırası korunur. SwiftData şeması değişmedi.

IPA SHA256: `d2ee023b9ac539190fb93d66153aa7bc43077351d6132f365257925d749d7279`.
