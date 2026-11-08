# KlyMusic — 2.6.0 (13), son kullanıcı kapsamı

Kullanıcı 2.5.0 oynatıcı ve söz tasarımını onayladı. Bu tur yalnızca üç nokta menüsü, çalma sırası ve diğer sayfaların görünümü içindir. Onaylanan oynatıcı yerleşimine, sözler/animasyona, native tab bar ve mini oynatıcıya dokunma. Protected-UI-Current.json bu alanları kaydeder.

Üç nokta menüsünde ilişkili işlemler gruplandı; çalan parçanın etkisiz sıra işlemleri kaldırıldı; sanatçı/albüm alt menüye alındı. Çalma sırası geçmiş/çalan kaydı tekrar göstermez; yalnızca gelecek parçalar sıralanır. Satır seçimi mevcut sırayı korur. Sürükleme eski bir liste görüntüsünden gelirse kimlik üzerinden çözülür; bu sırada çalmaya başlayan kayıt yerinden oynatılmaz. Temizleme mevcut çalan AVPlayerItem'ı kesmez.

Kapak renkleri ve kenar ışıkları YALNIZCA oynatıcıda kalır. Diğer sayfalar düz, nötr zemin kullanır. Zemini Color.musicBackground ile aynı tut; farklı renkli gezinme çubuğu/scroll dikişini geri getirme. Sayfa art alanına AlbumBackdrop ekleme.

Apple Music/iOS 27 araştırması Design-Research-2.6.0.md içindedir. Derleme Xcode 26.3; UI testi iOS 26 simülatöründe yapılır. iOS 27 cihaz testi yapılmış gibi yazılmaz.

Önceki ses/veri iyileştirmeleri korunur: varsayılan Az veri, taramada ses ön yükleme yok, sonraki hazır AVPlayerItem yeniden kullanılır, doğrulanmış kayıt eşleşmeleri 7 gün saklanır. 1 ms duyulabilir ses garantisi verilmez. Kontrol yolu ölçümü gerçek ses gecikmesi değildir. SwiftData ve cihazdaki kütüphane korunur.

Repo: https://github.com/KlyMorias0/KlyMusic (özel).
Derleme: bash scripts/build-ipa.sh, doğrulama: bash scripts/ci-verify.sh.
Güncel sonuç: VALIDATION-2.6.0.md; eski sürüm belgeleri tarihsel kayıttır.
