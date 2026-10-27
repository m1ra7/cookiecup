# CookieCup Native

Bu klasör, mevcut Flutter uygulamasından bağımsız native SwiftUI projesidir. Orijinal Flutter ZIP dosyası değiştirilmemiştir. Önceden bulunan ürün görselleri orijinal ZIP’in assets klasöründen alınmıştır. Eklenen 15 ürün için uyumlu ve şeffaf yeni illüstrasyonlar üretilmiştir; internetten rastgele ürün fotoğrafı kullanılmamıştır.

## Çalıştırma
1. Güncel bir macOS ve Xcode 14.2 veya daha yeni bir sürüm kullanın. Minimum hedef iOS 16.0’dır (Swift 5.7, ObservableObject ve Codable/UserDefaults).
2. CookieCup.xcodeproj dosyasını açın; CookieCup şemasını seçin.
3. Simulator seçip Run tuşuna basın. Gerçek cihaz için Signing & Capabilities altında kendi Team hesabınızı seçin ve gerekirse bundle identifier değiştirin.
4. Xcode 14.2 üzerinde iOS 16/16.2 Simulator seçin. Kullandığınız iPhone’un iOS sürümü Xcode tarafından desteklenmiyorsa önce Simulator ile deneyin.

## Özellikler
Home, filtrelenen/aranabilen Menu, Favorites, Cart ve Profile; ürün detayı, kahve seçenekleri ve dinamik fiyat; adet yönetimi, silme ve sepet temizleme; Codable + UserDefaults kalıcılığı; uygulama içi TR/DE/EN ve sistem/açık/koyu görünüm; yerel demo siparişi ve sipariş geçmişi. iPhone/iPad adaptif grid; Reduce Motion tercihini izleyen özel animasyonlar; native geçişler ve haptic feedback.

## Gerçek işletme kullanımı
Bu bir yerel demo uygulamasıdır. Checkout gerçek işletmeye sipariş göndermez, ödeme almaz veya stok ayırmaz. Gerçek kullanım için backend, ödeme, stok ve işletme paneli gerekir. Fiyatlar örnektir; ürün adları görsellerden eşleştirilmiştir. Tarif, alerjen, kalori ve değerlendirme verileri sağlanmadığından uydurma sayısal veriler gösterilmez. Kafe doğruladığında model genişletilmelidir. Çay, tatlı ve atıştırmalık kategorileri yeni örnek ürünler ve uyumlu üretilmiş illüstrasyonlarla genişletilmiştir.

## Doğrulama
Görsel dosyaları, katalog referansları, dil anahtarları ve Xcode proje yapısı statik olarak kontrol edilmiştir. Bu Linux ortamında Xcode/SwiftUI SDK bulunmadığı için Xcode 14.2 derlemesi ve iOS Simulator testi yapılamamıştır. Uyarlama statik olarak kontrol edilmiştir. İlk açılışta Simulator üzerinde derlenip aşağıdaki akışlar doğrulanmalıdır:
- Her üç dil ve iki temada ekranlar; büyük yazı boyutları ve yatay ekran.
- Favori ekleyip uygulamayı kapat/aç.
- Kahvede boyut/süt/ekstra seçip fiyatı kontrol et; aynı seçenekler birleşsin, farklı seçenekler ayrı kalsın.
- Sepette azalt/sil/temizle, kapat/aç, demo sipariş kaydet ve geçmişi kontrol et.
- Menu araması, tüm kategoriler ve boş kategoriler.

AssetMap.json ve catalog-audit.json orijinal dosya ile asset eşleşmesini belgeler. Orijinal görsel dosyalarının kullanım/yayın hakları bu çalışmayla doğrulanmış değildir.

## Xcode 14.2 uyarlaması
Görseller, katalog, fiyat hesapları, Swift dosyalarının ayrımı, dil dosyaları ve tüm ekran akışları korunmuştur. Observation yerine ObservableObject/@Published/@EnvironmentObject, SwiftData yerine mevcut Codable/UserDefaults kayıt formatı kullanılır. Swift 5.9 switch ifadeleri Swift 5.7 return ifadelerine çevrilmiştir. iOS 17 boş durum/animasyon/haptic API’leri iOS 16 karşılıklarıyla değiştirilmiştir. Bundle identifier ve `cookiecup.snapshot.v1` anahtarı aynıdır; eski sürümün her kayıtta oluşturduğu UserDefaults yedeği okunur. Mevcut kurulumun üzerine aynı bundle identifier ile yüklemek kayıtların korunmasını sağlar; uygulamayı silmek cihaz kayıtlarını siler.

## Referans ana sayfa
Koyu kahve zemin, orijinal caffe_makinesi kahve görseli, yatay kurabiye kartları ve gömülü Pacifico başlık fontu kullanılır. HomeView ve uygulama font başlangıcı güncellenmiştir. Alt gezinmedeki beş mevcut sekme korunur. Fonts/OFL.txt font lisansıdır. Son CartView derleyici düzeltmesi bu pakete dahildir.

## Genişletilmiş katalog
Katalog 37 üründür. Eklenen 15 ürünün görselleri yerleşik imagegen ile üretilmiştir; mevcut 50 görsel değişmeden korunur. Yeni ürünlerin isim, açıklama ve örnek fiyatları new-products.json içinde listelenir. Görseller gerçek işletme ürünlerinin fotoğrafı değildir. Yeni ürünler de sepete/favorilere eklenebilir ve aramada bulunabilir. Yeni çay/tatlı kategorilerinin detay ekranı metinleri üç dilde eklenmiştir.

## Yeni kahve seçenekleri
Espresso, Latte, Mocha, Cold Brew, Iced Vanilla Latte ve Iced Hazelnut Coffee eklendi. Coffee ve Cold Coffee kategorilerindeki tüm ürünlerin açıklamaları üç dilde ürün bazında hazırlanmıştır. Yeni 6 görsel de önceki ek ürünlerle aynı şeffaf illüstrasyon tarzındadır.
