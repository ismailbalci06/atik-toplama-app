import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_theme.dart';

/// Tasarimdaki durum rozeti (Tamamlandı / Yolda / Bekliyor).
///
/// Bilincli olarak GENERIC tutuldu: yalnizca metin ve renk alir.
/// Durum -> renk eslemesi feature katmaninda yapilir; boylece core
/// katmani domain modeline bagimli kalmaz.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  /// Hazir varyantlar — tasarim paletinden
  factory StatusBadge.success(String label) => StatusBadge(
        label: label,
        background: AppColors.successBg,
        foreground: AppColors.successInk,
      );

  factory StatusBadge.warning(String label) => StatusBadge(
        label: label,
        background: AppColors.warningBg,
        foreground: AppColors.warningInk,
      );

  factory StatusBadge.neutral(String label) => StatusBadge(
        label: label,
        background: AppColors.neutralBg,
        foreground: AppColors.neutralInk,
      );

  factory StatusBadge.danger(String label) => StatusBadge(
        label: label,
        background: const Color(0xFFFCE8E8),
        foreground: AppColors.error,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
