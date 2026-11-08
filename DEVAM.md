# KlyMusic — 2.5.0 (12), güncel kullanıcı düzeltmesi

Kullanıcı 2.4.1'de sözlere girince eski oynatıcıya dönülmesini reddetti. Korumak istediği TAM ESKİ LYRICS EKRANI DEĞİL, yalnızca söz satırlarının hareket/takip tasarımıdır. Tab bar da korunacaktır. Bu son açıklama önceki geniş koruma notlarının yerine geçer.

2.5.0'da tek oynatıcı kabuğu vardır: kapak/söz alanı değişir; metadata, sarma çubuğu, transport, ses seviyesi, footer ve kapak rengine bağlı ışıklar iki modda aynıdır. originalLyricsLayout ve eski oynatıcı yardımcıları kaldırıldı. LyricsView/AnimatedLyricLine kaynakları ve native tab bar/root değişmedi.

Kullanıcı saf siyah bir duvar istemiyor; kapak renginde yumuşak kenar ışıkları istiyor. Ana ekran daha kompakt bir dinleme alanı olarak, ayarlar da eski gri tablodan farklı kalite/görünüm/çevrimdışı/yedekleme alanlarıyla yeniden kuruldu. Yeni sloganlar eklenmez.

Varsayılan Az veri: düşük bit hızlı AAC tercihi, taramada ses ön yükleme yok, yalnızca sıradaki parça hazırlanır. Pahalı/kısıtlı bağlantıda tarama ön hazırlığı yapılmaz. Küçük kapaklar 160/320 piksel istenir; büyük kapak/rengin kaynağı aynı önbellekten paylaşılır. Sabitlenmiş eski kapaklar için disk alternatifi korunur.

Başarılı kayıt eşleşmeleri (CDN URL'si olmadan) 7 gün saklanır. Hazır AVPlayerItem sonraki geçişte yeniden kullanılabilir. Kullanıcı 1 ms istedi fakat 1 ms duyulabilir ses ya da internetten açılış garantisi fiziksel olarak verilmez. Kontrol yolu ölçümüyle gerçek ses gecikmesi karıştırılmaz.

Az veri tercihi indirmelere ve yedek/geri yüklemeye uygulanır. Eski yedeklerde kalite ayarıyla tutarlı mod geri yüklenir. SwiftData modeli ve mevcut kütüphane korunur.

Repo: https://github.com/KlyMorias0/KlyMusic (özel).
Araç: Xcode 26.3. Derleme: bash scripts/build-ipa.sh.
Doğrulama: VALIDATION-2.5.0.md ve Protected-UI-Current.json.
