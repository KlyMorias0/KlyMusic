# KlyMusic — güncel devam kaydı

8 Kasım 2026: 2.4.1 (11), siyah Apple Music stili.

Kullanıcının kabul edilen yönlendirmesi: saf siyah arka plan, Apple Music'e benzeyen sade düzen. Büyük sloganlar, mavi/gri zemin ve renkli gösterge kartları kaldırıldı. Oynatıcıda büyük kare kapak, altında metadata, ince sarma çubuğu ve çerçevesiz geri/oynat/ileri kontrolleri kullanılır.

Tab bar, mini oynatıcı, lyrics bileşenleri ve lyrics açıkken kullanılan eski tam düzen KESİNLİKLE korunacak. Protected-UI-Current.json kaynak karşılaştırmasını içerir.

Ses çözümlemesinde ilk doğrulanan AAC sonucu kullanılır; şarkı/sanatçı/süre ve medya başlığı kontrolleri korunur. Player JavaScript hazırlığı önbelleğe alınır ve eşzamanlı erişim güvenlidir. Gerçek iPhone'da gecikme ölçülmedi; CI canlı sağlayıcı denemesi uygun kayıt bulamadı. Kesin hız süresi iddia edilmez.

Güncel testler: 54 geçti, 1 canlı tanılama testi atlandı, 0 hata. VALIDATION-2026-11-08.md esas alınmalı. Önceki tarihli belgeler tarihsel kayıttır.

Repo: https://github.com/KlyMorias0/KlyMusic (özel).
Derleme: Xcode 26.3, bash scripts/build-ipa.sh.
Güncel IPA: dist/KlyMusic-unsigned.ipa, 2.4.1 (11), imzasız.
