# KlyMusic — 2.7.0 (14), son kullanıcı kapsamı

Kullanıcı oynatıcı, tab bar ve sözleri onayladı. Tüm NowPlaying.swift (mini oynatıcı, tam oynatıcı, sözler, sıra) ve KlyMusicApp.swift/root ile oynatıcıdaki TrackMenu korunur. Protected-UI-Current.json 2.6.0 kaynaklarıyla birebir eşleşmeyi kaydeder. Bu tur diğer sayfalar ve ses çözümlemesi içindir.

Dinle/Keşfet yatay kapak rafları, Arama kategori kartları/kitaplık kapsamı/sonuç filtreleri, Kütüphane kategori satırları ve Son Eklenenler, liste oluşturma/seçme, albüm/sanatçı detayları ve Ayarlar yeniden kuruldu. Ayarlar sistem Form'u ve alt seçim sayfalarıdır; eski büyük kalite kartlarını geri getirme. KlyMusic adı ve gerçek işlevleri korunur. Apple aboneliği, radyo veya desteklenmeyen ses özelliklerini taklit eden etkisiz kontroller eklenmez. Kaynaklar Design-Research-2.7.0.md içindedir.

Ses düzeltmeleri:
- Mashup/medley adındaki gerçek kayıtları engelleyen anahtar kelime filtresi kaldırıldı. Resmi ortak sanatçı yüklemelerinde istenen sanatçı başlıkta açıkça kredilendirilmişse ve yükleyici de bu kredilerden biriyse aynı kayıt kimliği kabul edilebilir. Yanlış kayıtları başlık, sanatçı/konuk sanatçılar ve gerçek ses süresi kontrolleri ayırır.
- Apple süre bilgisi eksikse bölge/US lookup denenir; başarısız metadata genel invalidResponse hatasına dönmez. Kimlik eşleşmesi ve adayın doğrulanan ses süresi kullanılabilir.
- Bazı GoogleVideo URL'leri dur parametresi taşımaz. YouTubeKit artık ses formatının approxDurationMs bilgisini aktarır. Signed URL süresiyle çelişen format süreleri reddedilir.
- Görünen ilk üç parçanın eşleştirmesi ve kısa ömürlü ortak oynatıcı kodu ses indirmeden hazırlanır. Eşzamanlı aynı eşleştirme tek isteği paylaşır. Sağlayıcı kodu beş dakika, doğrulanan kayıt kimliği yedi gün saklanabilir; CDN URL'leri kalıcı kayıt eşleştirme dosyasına yazılmaz.
- Önce YouTube Music şarkı kayıtları, gerekirse aynı kaydın video kopyaları ve aynı kayıt doğrulamasından geçen alternatif kaynak denenir. Kaynak başarısızlığı yanlış sanatçı/yanlış sürüme geçme izni değildir.
- Az veri hâlâ düşük bit hızlı AAC tercihi ve taramada ses ön yüklememe davranışıdır. Metadata/range doğrulaması için iki aday eşzamanlı denenebilir; bu tam şarkı ön yüklemesi değildir. Kategori görsel URL'leri yedi gün önbelleğe alınır.

Kullanıcı butona basınca bir saniyede çalma ve tüm kayıtların çalışmasını istedi. Sağlayıcı erişimi ve gerçek cihaz ses gecikmesi test edilmeden garanti yazılmaz. Sonuçlar VALIDATION-2.7.0.md ve Verification-2.7.0.json içindedir. Kontrol yolu/URL çözümleme ölçümleri duyulabilir ses gecikmesi değildir.

Repo: https://github.com/KlyMorias0/KlyMusic (özel).
Araç: Xcode 26.3; test cihazı iOS 26 simülatörü. iOS 27 için araştırma yapıldı, iOS 27 runtime testi yapılmış sayılmaz.
Derleme: bash scripts/build-ipa.sh. Test: bash scripts/ci-verify.sh.
SwiftData modeli ve mevcut kütüphane korunur. Eski sürüm doğrulama belgeleri tarihsel kayıttır.
