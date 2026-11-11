# Apple Music tasarım araştırması — 8 Kasım 2026

Kaynaklar:
- [Apple iPhone Kullanma Kılavuzu, iOS 27: Queue up your music](https://support.apple.com/guide/iphone/queue-up-your-music-ipha4521ef7d/27/ios/27): Playing Next yalnızca gelecekte çalacak parçaları gösterir; bir parçayı seçmek onu ve ardından gelenleri çalar. Geçmiş ve şu an çalan kayıt aynı listede tekrarlanmaz.
- [Apple HIG: Menus](https://developer.apple.com/design/human-interface-guidelines/menus): sistem menüleri, tanınır semboller, ilişkili işlemleri gruplama ve alt menüler.
- [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass): standart kontrollerin sistem görünümünü kullanmak, kontrol ve gezinme yüzeylerini özel renk katmanlarıyla örtmemek.
- [9to5Mac, 19 Haziran 2026: Apple Music in iOS 27 introduces new design changes in two key areas](https://9to5mac.com/2026/06/19/apple-music-in-ios-27-introduces-new-design-changes-in-two-key-areas/): sanatçı/albüm bilgi hiyerarşisi, ayrı öne çıkan yayın alanı ve Liquid Glass iyileştirmeleri. Bu kaynak beta dönemini anlatır; son sürümün birebir piksel ölçüsü olarak kullanılmaz.

Bu projeye uygulama:
- Üç nokta menüsünde beyaz/primary metin ve simgeler, kaydetme/sıra/ilgili içerik grupları; ilgili sanatçı ve albüm alt menüde. Şu an çalan parça için etkisiz sıra işlemleri gizli.
- Sırada kompakt “Şimdi çalıyor” alanı, yalnızca sonraki parçalar, sistem sürükleme tutamaçları. Silme satırın bağlam menüsünde; uyku ve temizleme tek seçenek menüsünde.
- Kullanıcının isteğiyle ana/keşfet/arama/kütüphane/ayarlar ve detay sayfaları nötr, düz yüzeyler kullanır. Gezinme çubuğu ile sayfa zemini aynı renktir. Kapağa bağlı kenar ışıkları yalnızca onaylı oynatıcıda kalır.
- Kullanıcı tarafından onaylanan native tab bar, mini oynatıcı, oynatıcı yerleşimi ve söz akışı değiştirilmez.

Derleme Xcode 26.3; arayüz doğrulaması iOS 26 simülatöründedir. iOS 27 cihaz/simülatör testi yapılmış sayılmaz; standart kontroller kurulu iOS sürümünün sistem görünümünü kullanır.
