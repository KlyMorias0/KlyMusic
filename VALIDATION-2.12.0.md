# KlyMusic 2.12.0 (19) — 10 Kasım 2026

[CI çalışması](https://github.com/KlyMorias0/KlyMusic/actions/runs/42770580879) başarılı. Kod: `53e738b6de665f4177838a746a58fbe48b9c5f03`.

- Release iPhoneOS ARM64 derlemesi geçti; iOS 17.0+, SDK iphoneos26.2, Xcode 26.3. IPA imzasızdır.
- 92 uygulama birim testi, 5 arayüz testi ve 21 YouTubeKit testi geçti: **118 başarılı, 4 atlanan, 0 başarısız test**.
- LRCLIB tam eşleşmesi bulunamadığında alternatif albümde aynı kayıt arandı; sanatçı, sürüm ve bilinen süre uyuşmazlıkları reddedildi. Zamanlı sonuç düz metne tercih edildi.
- Lyrics.ovh yedeği, Türkçe/Unicode ve slash içeren yol bileşenlerinin kodlanması, servis hatasında diğer kaynağın denenmesi, gerçek yokluk ile bağlantı hatasının ayrılması ve iptalde gecikmeli isteklerin durması test edildi.
- Düz sözlere zaman damgası uydurulmadığı; bilinmeyen süre/uyuşmayan albüm veya taşan zaman damgalarında sözlerin düz metne döndüğü doğrulandı. Bozuk veya boş içerik geçerli sonuç sayılmadı.
- Önbellek testleri eski biçimin okunmasını, sürüm/yaş sınırlarını, boş sonuç sonrası normal yeniden denemeyi, eski düz sözleri görünür tutarak zamanlı söze yükseltmeyi, çevrimdışı/boş yenilemede eldeki sözleri korumayı, taze sözlerde ağ isteği açılmamasını ve zamanlı sözün düz/enstrümantal sonuca düşürülmemesini doğruladı.
- 5 arayüz testi söz takibi/satırdan sarma, oynatıcı/sıra, native sekmeler ve kütüphane/arama/ayar gezinmesini tekrar doğruladı. NowPlaying.swift, KlyMusicApp.swift, Artwork.swift ve TrackMenu kaynakları 2.7.0 tabanıyla birebir aynı; SwiftData SavedTrack/SavedPlaylist şeması değişmedi.
- IPA ZIP bütünlüğü, sürüm/build, SHA256, cihaz platformu, ARM64 ve imzasız paket yapısı doğrulandı. Fixture kaynakları IPA'ya dahil değil.

## Kaynaklar ve sınırlar

LRCLIB /api/get ve /api/search, Lyrics.ovh /v1 uçları kullanılır. Veri tasarrufunda ilk istekte zamanlı söz bulunursa başka kaynağa veya aramaya istek gönderilmediği test edildi. LRCLIB arama satırları yerelde doğrulanır. Lyrics.ovh yalnızca düz metin döndürür ve yanıtında sanatçı/süre/zaman damgası yoktur; tam sanatçı/başlıkla sorgulanır, zamanlı sonuç diye sunulmaz. Spotify veya onun söz servisinden veri alınmaz; Spotify'da bulunan her kaydın bu kaynaklarda bulunacağı garanti değildir.

10 Kasım'da Linux ortamındaki gerçek HTTPS kontrollerinde LRCLIB Şımarık kaydına zamanlı/düz söz, Lyrics.ovh Tarkan/Şımarık ve Coldplay/Yellow kayıtlarına düz söz döndürdü; söz metni günlükte yayınlanmadı. Mac/iOS simülatöründeki canlı uygulama kaynağı kontrolünde Şımarık için zamanlı söz ve 1605 karakterlik düz metin alındı; söz gövdesi günlüğe yazılmadı. Sonuç Verification-2.12.0.json içindedir. Dış sağlayıcı kesintileri ve katalog kapsamı devam eder; bütün şarkılara söz bulunması garantisi verilmez.

Eski kayıtlı sözler korunur. Yeni önbellek zamanlı sözlerde 7 gün, düz sözlerde 24 saat, enstrümantal sonuçta 6 saat sonra yenilenir; eski biçim ilk kullanımda yenilenir. Geçerli kayıtlı sözler yenileme sırasında ve ağ hatasında görünür kalır. Başarısız/boş sonuç söz dosyasını silmez. Ses eşleştirme/çözümleme bu sürümde değiştirilmedi; gerçek iPhone, iOS 27, 1 saniyede ses başlangıcı veya toplam mobil veri tüketimi denenmedi.

IPA SHA256: `405e58228e4b05e6ed43f2dea08e04b7d9eff61ceda1888ce740d5008a99cbe9`.
