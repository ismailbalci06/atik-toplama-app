/// Turkiye cep telefonu numarasi normalizasyonu ve maskeleme.
///
/// Firebase E.164 bicimi bekler (+905321234567). Kullanicilar ise numarayi
/// cok farkli yazar: "0532 123 45 67", "532-123-45-67", "+90 532 1234567".
/// Bu sinif hepsini TEK bicime indirger; boylece "numaram gecerli ama
/// kabul etmiyor" tipi sinir vakalari dogrulama ekranina hic ulasmaz.
///
/// Saf fonksiyonlardir: Firebase'e, ekrana ya da ag'a bagimli degildir —
/// bu yuzden tamamen test edilebilir.
class TrPhone {
  TrPhone._();

  /// Turkiye ulke kodu
  static const String countryCode = '+90';

  /// Ulke kodundan sonraki hane sayisi (5XXXXXXXXX)
  static const int nationalDigits = 10;

  /// Kullanicinin yazdigini E.164'e cevirir; gecersizse null doner.
  ///
  /// Kabul edilen bicimler:
  ///   0532 123 45 67 / 05321234567 / 532 123 45 67 / 5321234567
  ///   +90 532 123 45 67 / 905321234567
  /// Kural: sonucta ulke kodundan sonra 10 hane olmali ve ilk hane 5
  /// (Turkiye'de tum cep hatlari 5 ile baslar).
  static String? normalize(String raw) {
    // Rakam disi her seyi at (bosluk, tire, parantez, arti)
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    // Ulke kodu varsa soy
    if (digits.startsWith('90') && digits.length > nationalDigits) {
      digits = digits.substring(2);
    }
    // Sehirlerarasi "0" onekini soy
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    if (digits.length != nationalDigits) return null;
    // Turkiye cep hatlari daima 5 ile baslar
    if (!digits.startsWith('5')) return null;

    return '$countryCode$digits';
  }

  /// Girilen metin gecerli bir numaraya cevrilebiliyor mu?
  static bool isValid(String raw) => normalize(raw) != null;

  /// Ekranda gosterim icin MASKELER: +90 5•• ••• •• 67
  ///
  /// Numarayi tam gostermek gereksiz bir kisisel veri ifsasidir; kullanici
  /// hangi numarayi dogruladigini son iki haneden zaten anlar.
  static String mask(String e164) {
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return e164;
    final last2 = digits.substring(digits.length - 2);
    return '$countryCode 5•• ••• •• $last2';
  }

  /// Yazarken okunakli bicim: 0532 123 45 67
  static String pretty(String e164) {
    final n = normalize(e164);
    if (n == null) return e164;
    final d = n.substring(countryCode.length); // 5XXXXXXXXX
    return '0${d.substring(0, 3)} ${d.substring(3, 6)} '
        '${d.substring(6, 8)} ${d.substring(8)}';
  }
}
