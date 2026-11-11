# Apple Music sayfaları — 2.7.0 tasarım referansları

Kullanıcı oynatıcı, tab bar ve sözleri onayladı; geri kalan sayfaların Apple Music düzeninde yeniden kurulmasını istedi. KlyMusic adı ve desteklediği gerçek işlevler korunur. Apple hesabı, abonelik, radyo veya Dolby/Lossless gibi desteklenmeyen işlevleri taklit eden etkisiz düğmeler eklenmez.

İncelenen kaynaklar:
- [Apple Support: Search for music](https://support.apple.com/guide/iphone/search-for-music-iph4b506b24d/ios). Resmi örnekteki iki sütun kategori kartları, başlık hiyerarşisi ve arama sonuçları referans alındı. Sayfadaki görsel eski bir iOS arayüzü de içerebilir; tab bar bu görsele göre değiştirilmez.
- [iOS 27.2 beta 1 Library ekranı, MacRumors](https://forums.macrumors.com/threads/everything-new-in-ios-27-2-beta-1.2489610/): siyah/beyaz kütüphane simgeleri, tek satır kategoriler ve sağda disclosure. Beta örneğidir, tüm iOS 27 sürümlerinin aynı olduğu iddia edilmez.
- [Apple Music iOS 27 sanatçı ve albüm düzenleri, 9to5Mac](https://9to5mac.com/2026/06/19/apple-music-in-ios-27-introduces-new-design-changes-in-two-key-areas/): büyük sanatçı görseli, ortalanmış kimlik, öne çıkan oynatma ve karıştırma eylemleri.
- [Apple Music ayar tabloları görseli, MacRumors](https://images.macrumors.com/article-new/2021/06/apple-music-spatial-settings.jpg): iç içe ayar sayfaları, grouped list satırları, disclosure ve seçili seçenekte onay işareti. Eski görsel yalnızca liste düzeni içindir; desteklenmeyen ses özellikleri eklenmez.
- [Apple HIG: Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) ve [Menus](https://developer.apple.com/design/human-interface-guidelines/menus).

Yeni düzen:
- Dinle/Keşfet: büyük kare kapaklı yatay raflar; eski yatay kahraman kartı ve hızlı işlem hapları kaldırıldı.
- Arama: Kategorilere göz at, Son Aramalar, KlyMusic/Kitaplığın kapsamı, En İyi Sonuç, şarkı/albüm/sanatçı filtreleri.
- Kütüphane: Çalma Listeleri, Sanatçılar, Albümler, Şarkılar, Favoriler ve İndirilenler satırları; Son Eklenenler ızgarası.
- Ayarlar: sistem Form'u, kalite alt sayfası, navigation-link dil/görünüm seçicileri, Wi-Fi ve depolama satırları, yedekleme grubu. Eski büyük kalite kartları kaldırıldı.
- Liste seçme/oluşturma: satırlı seçim ve ayrı sistem formu. Albüm/liste eylemleri aynı boydaki Çal/Karıştır düğmeleriyle sunulur.
- Tüm sayfa zeminleri nötrdür; sanatçı görselinin içindeki okunurluk geçişi sayfa arka planına yayılmaz.

Bunlar kaynaklara dayalı SwiftUI uygulama düzenleridir; Apple Music uygulamasının ikilisi veya özel kaynakları kopyalanmaz. Ekran görüntüleri ve Xcode sürümü son doğrulama belgesinde kayıtlıdır.
