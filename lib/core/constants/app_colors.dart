import 'package:flutter/material.dart';

/// ATOS marka renk paleti.
///
/// Kaynak: Hümeyra'nın Figma tasarımları + ATOS logosu.
/// Kimlik iki renkten kuruluyor:
///   • Derin lacivert  → kurumsal güven, başlıklar, ikincil aksiyonlar
///   • Canlı yeşil     → sürdürülebilirlik, ana aksiyonlar, başarı
///
/// ÖNEMLİ: Alan adları bilinçli olarak korundu (primary, secondary,
/// background, night, neon...). Böylece tüm ekranlar tek dosya
/// değişikliğiyle yeni kimliği giyiyor; ekran kodlarına dokunulmuyor.
class AppColors {
  AppColors._(); // Instance olusturulmasini engelle (sadece statik erisim)

  // --- Marka cekirdegi ---

  /// Ana marka rengi — ATOS yesili (ana butonlar, aktif durumlar)
  static const Color primary = Color(0xFF22A45D);

  /// Koyu yesil — gradyanin koyu ucu, basili buton durumu
  static const Color primaryDark = Color(0xFF17834A);

  /// Acik yesil — gradyanin acik ucu, vurgu
  static const Color primaryLight = Color(0xFF35BC6B);

  /// Derin lacivert — ATOS logo rengi; basliklar, giris butonu, koyu yuzeyler
  static const Color night = Color(0xFF1B3A5C);

  /// Laciverdin bir tik acigi — gradyan ara tonu
  static const Color nightSoft = Color(0xFF244B74);

  /// Neon/limon yesil — enerji vurgusu (koyu zeminde sayilar, rozetler)
  static const Color neon = Color(0xFF8FD64B);

  // --- Yuzeyler ---

  /// Sayfa arka plani — tasarimdaki soguk acik gri
  static const Color background = Color(0xFFF3F6FA);

  /// Kart/sheet yuzeyi
  static const Color surface = Colors.white;

  /// Girdi alani / pasif dolgu
  static const Color surfaceMuted = Color(0xFFF7F9FC);

  /// Ince kenarlik rengi (kartlar, girdiler)
  static const Color border = Color(0xFFE3E9F0);

  // --- Metin renkleri ---

  static const Color textPrimary = Color(0xFF13293F);
  static const Color textSecondary = Color(0xFF7C8AA0);

  /// Eski kodla uyumluluk: ikincil vurgu yesili
  static const Color secondary = Color(0xFF35BC6B);

  // --- Durum renkleri (talep rozetleri) ---

  /// Hata / iptal
  static const Color error = Color(0xFFE05252);

  /// "Tamamlandı" rozeti
  static const Color successBg = Color(0xFFE4F6EA);
  static const Color successInk = Color(0xFF17834A);

  /// "Yolda" rozeti
  static const Color warningBg = Color(0xFFFDF3DA);
  static const Color warningInk = Color(0xFFA9761A);

  /// "Bekliyor" rozeti
  static const Color neutralBg = Color(0xFFEDF1F6);
  static const Color neutralInk = Color(0xFF6B7A90);

  // --- Ortak dekorasyon parcalari ---

  /// Kartlarda kullanilan yumusak golge — tasarimdaki hafif, dagilmis golge.
  static const List<BoxShadow> softShadow = [
    BoxShadow(
      color: Color(0x0F1B3A5C), // laciverdin ~%6 opakligi
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Color(0x081B3A5C),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  /// Marka gradyani: lacivertten yesile — ATOS logosunun gecisi
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [night, nightSoft, primaryDark],
  );

  /// Ana aksiyon gradyani — tasarimdaki yesil "Talep Oluştur" butonu
  static const LinearGradient energyGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primaryDark, primaryLight],
  );
}
