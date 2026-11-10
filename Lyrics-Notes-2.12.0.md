# Çok kaynaklı şarkı sözleri — 2.12.0

10 Kasım 2026. Önceki sürüm yalnızca LRCLIB /api/get çağrısını ham parça/sanatçı/albüm/süreyle yapıyordu. 404 yanıtı doğrudan yokluk sayılıyor, düz/enstrümantal önbellek süresiz kullanılıyordu.

LRCLIB /api/search ile alternatif albüm baskıları ve kayıt yazımları aranır. Her satırın başlık/sanatçı kimliği ve bilinen kayıt süresi doğrulanır. Uyuşmayan sürüm/süre reddedilir. Zaman damgaları bilinen süre veya aynı albümle doğrulanamazsa gerçek metin düz gösterilir; hayali zamanlama üretilmez.

İkinci bağımsız kaynak Lyrics.ovh /v1/artist/title'dır. HTTPS, bileşen başına Unicode/slash kodlaması ve düz metin yanıtı kullanılır. Kaynak zaman, sanatçı veya süre metadatası döndürmediğinden yalnızca tam sanatçı/başlıkla sorgulanır ve zamanlı sonuç diye sunulmaz. Spotify/Musixmatch verisi veya hesabı kullanılmaz.

Veri tasarrufunda zamanlı tam eşleşme tek ağ isteğiyle sonuçlanır. Bulunamazsa LRCLIB arama ve Lyrics.ovh birlikte denenir. Diğer modda kısa gecikmelerle yedekler devreye girebilir. Doğrulanmış zamanlı söz düz metinden önceliklidir. 404 yokluk, servis/bağlantı hatası yeniden denenecek hata olarak ele alınır. Kaynaklardan biri hata verse diğeri kullanılabilir.

Önbellek yanıt, zaman ve çözümleyici sürümünü saklar; eski dosyaları okuyabilir. Boş/bozuk sonuç saklanmaz. Düz ve enstrümantal eski kayıtlar yeniden kontrol edilir; çevrimdışı sözler görünür kalır. İndirme sonrası söz kaydı da boş yanıtla silinmez veya zamanlıdan düz sonuca düşürülmez.

Gerçek HTTPS kontrolünde Tarkan/Şımarık için LRCLIB zamanlı/düz, Lyrics.ovh düz metin döndürdü; Coldplay/Yellow için Lyrics.ovh yanıtı da doğrulandı. Metin günlükte yayınlanmadı. Kaynak kapsamı ve ağ erişimi garanti değildir; Spotify'da bulunan her sözün burada da bulunması iddia edilmez. Son test sonuçları VALIDATION-2.12.0.md içindedir.

NowPlaying.swift, native tab bar, söz görünümü/satır animasyonu ve ses çözümleme hattı değiştirilmedi.

Son canlı CI kontrolü başarılı: Şımarık için zamanlı söz ve 1605 karakter düz metin alındı; 118 test başarılı, 4 canlı ses tanılaması sağlayıcı erişimi nedeniyle atlandı. Test metni günlükte yayınlanmadı.
