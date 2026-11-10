# iPhone'a kurulum — paket durumu

Bu tam teslim ZIP'inde kurulabilir dosya:

`artifacts/2.12.0/KlyMusic-2.12.0-unsigned.ipa`

Bu dosya 2.12.0 / build 19'dur. 2.13.0 genel oynatma kaynak değişikliklerini içermez. 2.13.0 için GitHub Mac derlemesi hesap engeli nedeniyle henüz çalışmadı.

1. IPA'yı ZIP'ten çıkar.
2. Kullandığın sideload aracıyla kendi Apple hesabın/sertifikan üzerinden imzala ve yükle.
3. Gerekirse aracın istediği geliştirici güvenini veya Geliştirici Modu işlemini iPhone'da tamamla.

Minimum dağıtım hedefi iOS 17.0; paket ARM64 iPhone/iPad Release derlemesidir. KlyMusic içine Apple ID/parola girilmez. App Store/TestFlight yayını değildir.

Son doğrulanan IPA SHA256:

`405e58228e4b05e6ed43f2dea08e04b7d9eff61ceda1888ce740d5008a99cbe9`

Daha sonra kaynaklardan yeni IPA üretildiğinde normal çıktı yolu `dist/KlyMusic-unsigned.ipa` olur. Ayrıntılı derleme, test ve devam bilgisi README.md / DEVAM.md içindedir.
