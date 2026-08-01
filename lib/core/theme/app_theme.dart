import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';

/// ATOS merkezi tema tanimi.
///
/// Hümeyra'nın tasarimindaki gorsel dil buradan yayiliyor: yumusak
/// yuvarlamalar, ince kenarlikli beyaz kartlar, soguk acik gri zemin,
/// kalin ve sikisik tipografi.
///
/// Tum ekranlar gorunumlerini buradan alir. Bir sey degistirmek
/// istedigimizde SADECE bu dosya ve app_colors.dart guncellenir.
class AppTheme {
  AppTheme._();

  /// Tasarimda kullanilan standart yuvarlama degerleri
  static const double radiusCard = 18;
  static const double radiusButton = 14;
  static const double radiusField = 14;
  static const double radiusBadge = 20;

  /// Acik (light) tema
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.night,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      // --- Yazi hiyerarsisi ---
      textTheme: base.textTheme.copyWith(
        // Ekran basliklari ("Hoş geldiniz", "Merhaba, ...")
        headlineSmall: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -0.6,
          height: 1.2,
        ),
        // Kart / bolum basliklari ("Son Talepler")
        titleMedium: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        // Liste satiri basligi
        titleSmall: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        // Govde metni
        bodyMedium: const TextStyle(
          fontSize: 14,
          color: AppColors.textPrimary,
          height: 1.45,
        ),
        // Ikincil/aciklama metni ("Hesabınıza giriş yapın")
        bodySmall: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          height: 1.45,
        ),
        // Kart altindaki kucuk etiketler ("Toplam Talep")
        labelSmall: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
          letterSpacing: 0.1,
        ),
      ),

      // --- AppBar: duz, temiz, golgesiz ---
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // --- Kartlar: beyaz, ince kenarlikli, yumusak yuvarlak ---
      // Material golgesi kapali; yumusak golgeyi widget'lar
      // AppColors.softShadow ile kendisi verir.
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),

      // --- Ana butonlar: yesil, dolgun, yuvarlak ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.3),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // --- Ikincil butonlar: seffaf, kenarlikli ("Hesap Oluştur") ---
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.night,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          side: const BorderSide(color: AppColors.border, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // --- Metin butonlari ("Şifremi Unuttum") ---
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // --- Cip'ler (atik turu secimi) ---
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surfaceMuted,
        selectedColor: AppColors.primary.withOpacity(0.12),
        checkmarkColor: AppColors.primaryDark,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),

      // --- Bottom sheet: ust koseleri genis yuvarlak ---
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),

      // --- Alt navigasyon (tasarim dili hazir olsun) ---
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),

      // --- Snackbar: yuvarlak, yuzen, lacivert ---
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.night,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusButton),
        ),
      ),

      // --- Girdi alanlari (tasarimdaki e-posta/sifre kutulari) ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13.5,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),

      // --- Slider (miktar secimi) ---
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: AppColors.primary,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withOpacity(0.12),
        inactiveTrackColor: AppColors.primary.withOpacity(0.15),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

/// Dokunsal geri bildirim yardimcisi.
///
/// Tum butonlar ayni his icin bunu kullanir; ileride siddet/desen
/// degistirmek istersek tek satir degisir.
class Haptics {
  Haptics._();

  /// Hafif dokunus — buton tiklamalari icin standart
  static void tap() => HapticFeedback.lightImpact();

  /// Orta siddet — onemli aksiyonlar (Talebi Al, Talep Olustur)
  static void action() => HapticFeedback.mediumImpact();

  /// Basari titresimi — kutlama/varis anlari
  static void success() => HapticFeedback.heavyImpact();
}
