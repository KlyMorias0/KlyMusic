# Ses çözümleme düzeltmeleri — 2.11.0

Kullanıcı Sigma Boy aramasında “Bu kaydın aynı sürümü kaynaklarda çalınamıyor” hatası bildirdi. Kod, parantezli Kiril başlığı Latin başlığın ek sözcükleri sayıyordu. Apple'ın herkese açık arama yanıtı 8 Kasım 2026'da 1833553551 kimliği, Sigma Boy (Сигма Бой), Betsy & Maria Iankovskaia ve 134400 ms süresini doğruladı.

Eşdeğer iki dilli başlık normalleştirmesi ve bu sanatçıların açık alternatif yazımları eklendi. Remix/live/sped-up ile eksik/yanlış krediler eşleşmez. Video sonucunda süre etiketi yoksa bilinen istek süresi gerçek medya süresiyle ayrıca doğrulanır. Asıl sürüm adı kaybolmaz.

Önceki kaynak sırası ardışık YouTube şarkı → YouTube video → alternatif kaynak biçimindeydi. Yeni akış kısa gecikmelerle kaynakları yarıştırır; doğrulanan ilk sonuç kullanılır. Kalıcı eşleşme ve ortak arama/oynatıcı bağlamı bekleyicileri iptale duyarlıdır. Son bekleyici ayrılırsa iş iptal edilir; eski sonuç yeni işi değiştiremez.

Range doğrulamasının data(for:) çağrısı sunucu Range'i yok saydığında bütün dosyayı bekleyebilirdi. Yeni delegate ilk 12 kapsayıcı baytını saklar, sonucu belirler ve görevi/oturumu iptal eder. İletişimde paket veya URLSession tamponu nedeniyle daha fazla bayt gelebilir; 12 bayt toplam ağ tüketimi iddiası yoktur.

Yeni testler eşleştirme, yanlış sürüm reddi, gerçek medya süresi, ortak istek iptali, geç yanıt koruması, HTTP 200/Range ve çıkarıcı yedeklerine odaklanır. Son sonuçlar VALIDATION-2.11.0.md içindedir. Canlı ses/gerçek iPhone başlangıcı başarılı ölçülmeden 1 saniye veya tüm şarkıların çalması iddia edilmez.

Onaylanan oynatıcı/sözler/tab bar tasarımı ve ses kalitesi tercihi korunur.

Canlı CI sonucu: Sigma Boy şarkı aramasında tVSCbJZ54tc doğru aday olarak eşleşti. YouTube oynatıcı istemcileri LOGIN_REQUIRED/bot doğrulaması döndürdüğü için ses çözümü alınamadı. Eşleşme düzeltmesi canlı arama verisinde doğrulandı; uçtan uca çalma doğrulanmadı.
