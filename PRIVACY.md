# KlyMusic veri akışı

KlyMusic kullanıcı hesabı, e-posta, Apple ID veya YouTube çerezi istemez. Favoriler, çalma listeleri, takip edilen sanatçılar, son aramalar, dinleme geçmişi, ayarlar ve indirilen dosyalar cihazda tutulur. Dışa aktarılan JSON yedeği kütüphane bilgilerini ve ayarları içerir; indirilen ses dosyaları içermez.

Release uygulaması arama metnini ve parçanın eşleştirme bilgilerini doğrudan ilgili katalog, ses ve söz sağlayıcılarına gönderir. Katalog/görseller Apple'dan, ses bağlantıları JioSaavn ve YouTube'dan, sözler LRCLIB ve Lyrics.ovh üzerinden alınır. Söz aramasında parça/sanatçı adı, LRCLIB tam eşleşmesinde varsa albüm adı ve süre gönderilir. Sözler ve önbelleğin yenileme bilgisi cihazda saklanır. Görseller cihazda önbelleğe alınır. Bu bağlantılarda ilgili sağlayıcılar standart bağlantı bilgilerini, örneğin IP adresini, görebilir. KlyMusic'e ait ayrı bir üretim sunucusu kullanılmaz.

Uygulama içi analitik, reklam SDK'sı veya takip için cihaz tanımlayıcısı yoktur. Debug derlemesinde geliştirici açıkça `-serverURL` argümanı verirse istekler bu test sunucusundan geçirilebilir; Release derlemesinde bu seçenek devre dışıdır.
