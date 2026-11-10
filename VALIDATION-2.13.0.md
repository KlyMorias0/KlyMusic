# KlyMusic 2.13.0 (20) — kaynak adayı, 10 Kasım 2026

Yeni iOS derlemesi ve tam arayüz/canlı ses testleri **çalışmadı**. [GitHub Actions işi](https://github.com/KlyMorias0/KlyMusic/actions/runs/42775580626) hiçbir adım başlamadan hesap engeliyle durdu:

> The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings

Bu paket için yeni IPA üretilmedi. Son doğrulanmış iPhone IPA sürümü 2.12.0'dır. Kaynak paketi eski IPA'yı içermez.

## Gerçekten çalıştırılan kontroller

Resmî Swift 6.0.3 Linux derleyicisiyle, üretim dosyalarından çıkarılan kod ve repodaki gerçek XCTest yöntemleri çalıştırıldı. **17 test geçti, 0 hata**:

- Genel kimlik motoru: 5 test. İçinde 12 dilde 480 kabul/720 ret kontrolü, toplam 1.200 üretilmiş metadata senaryosu var. Bunlar gerçek şarkı çalma sayıları değildir.
- Orijinal ses etiketleri, eksik varsayılan ses alanı ve hata sınıflandırması: 7 test. Üretimdeki decoder/filtre ve test fixture'ları kullanıldı.
- Ortak çözümleyici, arama ve stream önbelleği: 5 test. İlk üç başarısız kopyadan sonra dördüncüye geçiş, sonraki genel sorgunun denenmesi, önbellek/yenileme, kaynak engeli/eşleşme yok ayrımı ve sanatçı parser'ı doğrulandı. HTTP/ses cevapları enjekte edilir; gerçek CDN çıkarıcıları bu harness'te kullanılmaz ve çağrılırsa hata verir.

Değişen Swift dosyaları sözdizimi kontrolünden geçti. iOS/AVPlayer/JavaScript imza çözümü, gerçek YouTube erişimi, cihazda gecikme, tüm katalog kapsamı ve tam uygulama linkleme/derleme doğrulanmadı. Linux kontrolleri iPhone derlemesinin yerine geçmez.

Oynatıcı/söz animasyonu/native tab bar/kapak kaynakları 2.7.0 tabanıyla, SavedTrack/SavedPlaylist şemaları da önceki şemayla byte düzeyinde aynı. Şarkı/sanatçı adı istisna tabloları ortak kimlik motorundan kaldırıldı. Kaynak kod dosya özetleri Verification-2.13.0.json içindedir.

## Tekrar çalıştırma

```sh
python3 scripts/test-recording-identity-portable.py --swiftc /path/to/swiftc
python3 scripts/test-audio-metadata-portable.py --swiftc /path/to/swiftc
python3 scripts/test-resolver-portable.py --swiftc /path/to/swiftc
```

GitHub hesabındaki ödeme/harcama limiti engeli giderildiğinde `.github/workflows/ios.yml` yeniden çalıştırılmalı. Xcode derlemesi, 107 uygulama testi, 5 seçilmiş arayüz testi, 28 paket testi ve canlı tanılamalar tamamlanmadan 2.13.0 kurulabilir sürüm diye sunulamaz. Sayılar planlanan test kapsamıdır, tamamlanmış iOS sonucu değildir.
