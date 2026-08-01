import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// ATOS logo bileseni — orijinal marka gorseli.
///
/// Logo dosyasi: `assets/images/atos_logo.png` (1024x352).
/// Gorselin kendi icinde "ADVANCED TECHNOLOGY & OPTIMIZED SUSTAINABILITY"
/// alt basligi bulundugu icin [showTagline] varsayilan olarak KAPALI.
///
/// Tum ekranlar bu widget'i kullanir; logo degisirse tek dosya guncellenir.
class AtosLogo extends StatelessWidget {
  const AtosLogo({
    super.key,
    this.height = 48,
    this.showTagline = false,
  });

  /// Logonun yuksekligi (genislik oransal: ~2.9:1)
  final double height;

  /// Altina Turkce alt baslik eklensin mi
  final bool showTagline;

  static const String assetPath = 'assets/images/atos_logo.png';

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      assetPath,
      height: height,
      fit: BoxFit.contain,
      // Gorsel yuklenemezse uygulama cokmesin: sade bir yazi isaretine dus
      errorBuilder: (_, __, ___) => Text(
        'ATOS',
        style: TextStyle(
          fontSize: height * 0.7,
          fontWeight: FontWeight.w800,
          color: AppColors.night,
          letterSpacing: -1,
        ),
      ),
    );

    if (!showTagline) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: 4),
        Text(
          'Atık Toplama Sistemi',
          style: TextStyle(
            fontSize: height * 0.21,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
