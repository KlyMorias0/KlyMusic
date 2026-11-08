# KlyMusic 2.11.0 (18) — 8 Kasım 2026

[CI çalışması](https://github.com/KlyMorias0/KlyMusic/actions/runs/42529108113) başarılı. Kod: `edc2d5b1992aa87814c078e46f2219a0e4d630b2`.

- Release iPhoneOS ARM64 derlemesi geçti; iOS 17.0+, SDK iphoneos26.2, Xcode 26.3. IPA imzasızdır.
- 76 uygulama birim testi, 5 arayüz testi ve 21 YouTubeKit testi geçti: **102 başarılı, 4 atlanan, 0 başarısız test**.
- Başlık eşleştirme testleri Latin/Kiril çift başlığın aynı kaydı bulmasını, bilinen sanatçı yazımlarını, remix/live/sped-up ve eksik/yanlış sanatçı reddini doğruladı. Parantezli her metin silinmez; yalnızca aynı transliterasyonu veren iki dildeki başlık ayrılır.
- Video aramasında süre yoksa sadece kimliği eşleşen ve istenen süresi bilinen aday akış denemesine geçebilir; gerçek medya süresi ayrıca doğrulanır. Doğrudan YouTube kimliğiyle gelen kayıtta süreyi gerçek medyadan öğrenme testi de geçti.
- Kontrol testleri iptal edilen ortak arama bekleyicisinin diğerini durdurmadığını, hazır bağlantının 30 saniyelik sahte yavaş aramayı beklemediğini, son bekleyici ayrılınca işin iptal edildiğini ve eski oynatıcı bağlamının yeni sonucu ezmediğini doğruladı. Bu ölçümler ağ veya duyulabilir ses başlangıcı değildir.
- Ses başlığı testleri HTTP 200 ile Range isteğini yok sayan sunucuda ilk 12 bayt alındıktan sonra aktarımın iptal edilmesini, yanlış kapsayıcı/HTTP hatası reddini ve iptal akışını doğruladı. Bu bir cihazdaki toplam veri tüketimi ölçümü değildir.
- Hızlı YouTube bağlamı hata verirse tam çıkarıcıya geçiş; başarılı hızlı yanıtın yedeği çalıştırmaması ve iptal edilen işin yeniden istek açmaması test edildi.
- 5 arayüz testi oynatıcı/sözler/sıra, native sekmeler, yerel/katalog araması, kütüphane ve ayar gezinmesini tekrar doğruladı. Onaylanan NowPlaying.swift, KlyMusicApp.swift, Artwork.swift ve TrackMenu kaynakları 2.7.0 tabanıyla birebir aynı; SwiftData şeması değişmedi.
- IPA bütünlüğü, sürüm/build, SHA256, cihaz platformu, ARM64 ve imzasız paket yapısı doğrulandı. Fixture dosyaları IPA içinde yoktur.

## Canlı kontrol ve sınırlar

Sigma Boy için Apple katalog kaydı 1833553551, başlık Sigma Boy (Сигма Бой), sanatçılar Betsy & Maria Iankovskaia ve süre 134,4 saniye Apple arama yanıtından doğrulandı. Canlı tanılama bu gerçek kimliği kullanır. Canlı YouTube şarkı araması Betsy, Мария Янковская kredili 135 saniye etiketli tVSCbJZ54tc kaydını buldu ve aday kabul etti. Ses çıkarımında istemciler LOGIN_REQUIRED / “Sign in to confirm you’re not a bot” döndürdü; çalma doğrulanamadı.

4 canlı ses tanılaması çalınabilir akış alınamadığı için atlandı. Tüm katalog kayıtlarının çalması, fiziksel iPhone'da 1 saniyede duyulabilir başlangıç ve toplam mobil veri tüketimi doğrulanmadı. YouTube erişimi sağlayıcı/bölge/ağ koşullarına bağlıdır. Linux ortamındaki YouTube arama tanılaması proxy tarafından HTTP 403 ile engellendi; bu, telefonda alınan sağlayıcı yanıtıyla aynı şey değildir.

Kaynaklar artık kısa aralıklarla devreye girerek yarışır; ana kaynak hatasının tamamen bitmesi yedeklerin başlaması için gerekmez. Bu, yavaş ana kaynaklarda sıralı beklemeyi azaltır; yavaş ağda ek metadata isteği oluşturabilir. Ses kalitesi tercihi korunur ve doğrulama başlıkla sınırlanır. Bir saniye veya Spotify ile eşit veri tüketimi garantisi verilmez. Fiziksel iPhone ve iOS 27 denenmedi.

IPA SHA256: `beb914367201b37a59ef841095c0bf26ea98c5b63c4a1cd1b00c1821c1a1746e`.
