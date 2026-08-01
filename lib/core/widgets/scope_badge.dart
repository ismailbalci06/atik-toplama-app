import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_theme.dart';

/// Bir istatistik blogunun KAPSAMINI gosteren kucuk rozet.
///
/// Neden var: uygulamada iki farkli kapsamda sayac gosteriliyor —
/// Rol Secim ekranindaki pano SISTEM GENELI (tum kullanicilarin
/// tamamlanmis teslimatlari), Ana Sayfa ve Rapor ekranindakiler ise
/// KULLANICIYA OZEL. Rakamlarin birbirini tutmamasi normaldir; bu rozet
/// farkin bir sayac senkronizasyon hatasi degil KAPSAM farki oldugunu
/// ekranda acikca yazar.
///
/// Yalnizca etiket seviyesinde bir isarettir: veri akisina veya
/// hesaplamaya hicbir etkisi yoktur.
class ScopeBadge extends StatelessWidget {
  const ScopeBadge({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  /// Tum ATOS kullanicilarini kapsayan veri
  factory ScopeBadge.global([String label = 'Sistem geneli']) => ScopeBadge(
        icon: Icons.public_rounded,
        label: label,
      );

  /// Yalnizca oturum acan kullanicinin kendi verisi
  factory ScopeBadge.personal([String label = 'Size özel']) => ScopeBadge(
        icon: Icons.person_outline_rounded,
        label: label,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.neutralBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.neutralInk),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.neutralInk,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
