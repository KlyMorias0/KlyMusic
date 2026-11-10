# Genel oynatma güncellemesi — 2.13.0 kaynak adayı

Bu çalışma şarkı/sanatçı adına özel istisna tablosunu kaldırır. Bütün kayıtlara aynı RecordingIdentity kuralları uygulanır: tam başlık/sürüm, ortak ve konuk sanatçı kredileri, desteklenen Unicode/transliterasyon, sunum etiketleri ve güvenilir yükleyici kredileri.

İlk birkaç kopya başarısız olunca sonraki uygun kopyalar ve genel sorgular denenir. Aynı medya kimliği/kalite/süre istekleri ortak önbelleği kullanır. Oynatma hatasında medya önbelleği yenilenebilir. YouTube arama parser'ı bazı eksik sanatçı tür etiketlerini ve işaretsiz ortak kredi metnini korur.

YouTubeKit'teki orijinal ses filtresi English (Original) gibi parantezli/yerelleştirilmiş etiketleri tanır. audioIsDefault eksikliği tüm yanıtı bozmaz; varsayılan işaret tek başına orijinal kabul edilmez. Kaynak giriş doğrulaması, erişim, ağ, bozuk medya ve eşleşme yok sonuçları ayrılır. Giriş engelini aşma yöntemi eklenmedi.

Linux Swift ile 17 test geçti. Bunların içinde 12 dilde 1.200 üretilmiş metadata kontrolü var; bunlar gerçek şarkı çalma sayıları değildir. Resolver testleri enjekte edilmiş HTTP/ses kullanır. iOS/AVPlayer ve canlı katalog başarısı bu sürümde doğrulanmadı.

GitHub Mac işi hesap ödeme/harcama limiti nedeniyle hiçbir adım başlamadan durdu. 2.13.0 IPA yoktur; tam ZIP'e konulan IPA son doğrulanan 2.12.0'dır. README ve VALIDATION-2.13.0.md ayrıntıları açıklar.
