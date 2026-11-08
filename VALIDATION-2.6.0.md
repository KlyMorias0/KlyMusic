# KlyMusic 2.6.0 (13) — 8 Kasım 2026

[Son CI çalışması](https://github.com/KlyMorias0/KlyMusic/actions/runs/42470272945) başarılı.
Kod: `c2898ff21d12150d8710426f3253b0958dcab90e`.

- Release iPhoneOS ARM64 cihaz derlemesi geçti. iOS 17.0+, SDK iphoneos26.2, Xcode 26.3. Paket imzasızdır.
- 48 uygulama birim testi, 4 arayüz testi ve 12 YouTubeKit testi geçti: toplam 64 başarılı test, 0 hata. Bir canlı sağlayıcı tanılaması CI'dan uygun kayıt bulamadığı için atlandı.
- Onaylı oynatıcı ve söz kaynakları (NowPlaying.swift içinde QueueView öncesi), AirPlay/ses kontrolleri, kapak/renk çıkarımı ve native tab bar/root 2.5.0 ile birebir aynı. Mini oynatıcı ve söz satırı akışı/animasyonu da değişmedi. Kapsam Protected-UI-Current.json içindedir.
- Yeni sıra testleri geçmişin ve çalan parçanın sonraki listede görünmemesini, korunan parçaların silinememesini, kimlikle sıralama işlemini ve sürükleme sırasında çalmaya başlayan parçanın yerinden oynatılmamasını doğruladı.
- Sıradan parça seçimi var olan sırayı korur; hazır AVPlayerItem nesnesi yeniden kullanılabilir. Sırayı temizleme mevcut çalan AVPlayerItem'ı kesmez. Kontrol yolu tanılaması duyulabilir ses gecikmesi değildir; bu sürümde yeni bir ses/hız/veri tüketimi ölçümü iddia edilmez.
- Arayüz testi menüden listeye ekleme sayfasının açılmasını, çalan parça için etkisiz sıra işlemlerinin gizlenmesini, gelecek üç parçanın görüntülenmesini, sıradan bir parçanın seçilmesini, ardından gelen parçaların korunmasını ve sıranın temizlenmesini doğruladı.
- Native sekme gezinmesi açık/koyu temada, söz takibi ve satıra dokunarak sarma, sözler açıldığında oynatıcı kontrollerinin konum/boyutunu koruması ve kalite seçimi testleri geçti.
- Menü, sıra, kaydırılmış ve yukarı çekilmiş ana sayfa, ayarlar görüntüleri incelendi. Sayfa ve gezinme alanı aynı nötr zemini kullanır. Kapak renkleri yalnızca onaylı oynatıcıda kalır.
- IPA ZIP bütünlüğü, SHA256, sürüm/build, iPhoneOS platformu, ARM64 Mach-O yapısı ve imzasız paket doğrulandı. Test kapağı uygulama paketine dahil değildir.

## Sınırlar

Arayüz doğrulaması iPhone 17 Pro / iOS 26 simülatöründe yapıldı. iOS 27 tasarımları araştırıldı; kaynaklar Design-Research-2.6.0.md içindedir. iOS 27 cihaz/simülatör testi veya fiziksel iPhone testi yapılmış sayılmaz.

Görseller yerel test sesi ve metadata'sını kullanır; gerçek YouTube oynatımını kanıtlamaz. Canlı sağlayıcı tanılaması atlandı. Önceki veri tasarrufu ayarları korunur; bu turda gerçek mobil veri tüketimi veya duyulabilir geçiş gecikmesi ölçülmedi.

IPA SHA256: `ba148895159cd84bf6cd96b1d2a73f5f87f270285de71fc973b4a53180c01ccb`.

Önceki sürüm belgeleri tarihsel kayıttır. Güncel sonuç bu belgedir.
