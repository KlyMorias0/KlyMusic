# Music sayfaları — 2.8.0

8 Kasım 2026. Referanslar:

- https://music.apple.com/tr/search?l=tr — gerçek editoryal kategori görselleri, başlıklar ve Music storefront içeriği. Albüm kapaklarını renklendiren eski kartlar kaldırıldı. Metadata yedi gün saklanır; görsel önbelleği mevcut Artwork bileşenidir. Kategori seçimi desteklenen katalog aramasını açar; abonelik/radyo/uzamsal ses hizmeti taklit edilmez.
- https://developer.apple.com/documentation/swiftui/view/searchscopes(_:activation:_:) — sistem arama kapsamları. Kapsam çubuğu metin girişiyle açılır; custom ikinci kapsam çubuğu kaldırıldı.
- https://developer.apple.com/documentation/swiftui/searchscopeactivation/ontextentry — kapsamların görünme davranışı.
- https://music.apple.com/tr/artist/tarkan/102640 — gerçek sanatçı portresi ile albüm kapağı ayrımı, çıkan eserler.
- https://9to5mac.com/2026/06/19/apple-music-in-ios-27-introduces-new-design-changes-in-two-key-areas/ — sanatçı başlığı altındaki oynat/takip kontrolleri ve ayrı yayın kartı düzeni.

Arama: düz zemin, iki sütun editoryal kategori görselleri, sistem arama alanı/kapsamı, tek filtre satırı, tekrar etmeyen sonuç başlığı, karma sonuçlarda kompakt albüm ve sanatçı satırları.

Ana sayfa: büyük kapak rafı, üçlü kompakt listeler; kayıt kimliğine göre tekrarlar elenir. Dinleme/favori sanatçılarından gerçekten katalog verisi gelirse Senin için gösterilir. Yeni kullanıcıya Öne çıkanlar gösterilir. Son dinlenen parçalar öne çıkanlarda ve listelerde tekrarlanmaz. Görünür parçalara ön hazırlık kişisel öneriler de geldikten sonra uygulanır.

Ayarlar: gereksiz logo alanı kaldırıldı. Dinleme, indirilenler ve görünüm kısa native gruplardır. Yedek ve geçmiş işlemleri Kütüphane ve Veriler alt sayfasına; sürüm/lisanslar Hakkında alt sayfasına taşındı. Desteklenmeyen hesap/abonelik özellikleri eklenmedi.

Kütüphane: beş ana satır; favoriler ve geçmiş seçenekler menüsünde, favoriler ayrıca listeler içinde. Son Eklenenler ilk kayıt sırasına dayanır ve tekrar dinleyince değişmez. Eski veritabanlarında eklenme tarihi olmadığı için sıra bir kez mevcut veriden başlatılır; SwiftData şeması değişmedi.

Sanatçı: gerçek portre varsa kullanılır; yoksa kişi yer tutucusu gösterilir. Albüm resmi profil resmi yapılmaz. Ayrı Son Çıkan/Yakında/Öne Çıkan kartı yayın tarihine göre adlandırılır.

Tam, mini oynatıcı; tab bar; şarkı sözleri; sıra; oynatıcı menüsü ve Artwork.swift birebir korundu. Görsel dil ve yerleşimler Apple Music referanslarını izler. Fiziksel cihazda piksel eşitliği ve iOS 27 runtime testi yapılmadan bunların birebir doğrulandığı iddia edilmez.

scripts/fixtures içindeki kategori görselleri gerçek editoryal görsellerdir; kaynakları category-sources.json dosyasındadır. artist.jpg sanatçı portresidir; artist-source.json kaynağı içerir. Bunlar yalnız test fixture sunucusunda kullanılır ve IPA içine eklenmez.
