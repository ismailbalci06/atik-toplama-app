import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_theme.dart';

/// Etki Panosu — tasarimdaki 3'lu istatistik kart dizilimi.
///
/// Degerler GERCEK: Firestore'daki tamamlanmis teslimatlardan hesaplanan
/// [impactStatsProvider]'dan gelir. Bu widget "aptal" (dumb) — sadece
/// verilen degerleri cizer; boylece core katmani feature'a bagimli kalmaz.
///
/// Gorsel: beyaz zemin, ince kenarlik, yumusak yuvarlama; ustte buyuk
/// kalin sayi, altta kucuk gri etiket (Hümeyra'nın tasarimi).
///
/// KAPSAM: Bu pano hangi veriyi gosterdigini kendisi bilmez — cagiran ekran
/// [scopeBadge] ve [scopeNote] ile yazar. Ayni sayaclarin kisisel surumu
/// Ana Sayfa'da oldugu icin bu etiket bilincli olarak zorunlu degil ama
/// her kullanimda verilmeli (bkz. ScopeBadge).
class ImpactDashboard extends StatelessWidget {
  const ImpactDashboard({
    super.key,
    this.treesSaved = 0,
    this.co2PreventedKg = 0,
    this.wasteRecycledKg = 0,
    this.deliveries = 0,
    this.loading = false,
    this.compact = false,
    this.title = 'Çevresel Etkimiz',
    this.scopeBadge,
    this.scopeNote,
  });

  /// Kurtarilan agac (kagit tonajindan) — su an baslikta ozet olarak kullanilir
  final double treesSaved;

  /// Onlenen karbon salinimi (kg CO2e)
  final double co2PreventedKg;

  /// Geri kazanilan toplam atik (kg)
  final double wasteRecycledKg;

  /// Tamamlanmis teslimat sayisi
  final int deliveries;

  /// Veri Firestore'dan henuz gelmediyse
  final bool loading;

  /// Dar gosterim (harita ustu serit)
  final bool compact;

  /// Bolum basligi
  final String title;

  /// Sayilarin kapsamini gosteren rozet (ornegin ScopeBadge.global())
  final Widget? scopeBadge;

  /// Kapsami tek cumleyle acan alt ibare
  final String? scopeNote;

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompactRow();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Bolum basligi + canlilik rozeti ---
        // Baslik Expanded: dar ekranda rozetle catisip tasma cizgisi
        // olusturmasin (Spacer yerine bilincli tercih).
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            _buildLiveTag(),
          ],
        ),

        // --- Kapsam etiketi: bu sayilar KIMIN verisi? ---
        if (scopeBadge != null || scopeNote != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (scopeBadge != null) ...[
                scopeBadge!,
                const SizedBox(width: 8),
              ],
              if (scopeNote != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      scopeNote!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),

        // --- 3'lu istatistik kartlari ---
        Row(
          children: [
            Expanded(
              child: _StatCard(
                value: deliveries.toDouble(),
                decimals: 0,
                label: 'Toplam\nTeslimat',
                loading: loading,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                value: wasteRecycledKg,
                decimals: 0,
                suffix: ' kg',
                label: 'Kurtarılan\nAtık',
                loading: loading,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                value: co2PreventedKg,
                decimals: 0,
                suffix: ' kg',
                label: 'Önlenen\nCO₂',
                loading: loading,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Verinin GERCEK ve canli oldugunu belirten kucuk rozet
  Widget _buildLiveTag() {
    late final String text;
    if (loading) {
      text = 'hesaplanıyor…';
    } else if (deliveries == 0) {
      text = 'ilk teslimat bekleniyor';
    } else {
      text = '${treesSaved.toStringAsFixed(1)} ağaç kurtarıldı';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!loading && deliveries > 0) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: const TextStyle(
              color: AppColors.successInk,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Harita ustunde tek satirlik dar gosterim
  Widget _buildCompactRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _CompactStat(text: '$deliveries teslimat'),
          _CompactStat(text: '${wasteRecycledKg.round()} kg atık'),
          _CompactStat(text: '${co2PreventedKg.round()} kg CO₂'),
        ],
      ),
    );
  }
}

/// Tek bir istatistik karti: buyuk sayi + kucuk etiket.
/// Sayi 0'dan hedefe SAYARAK yukselir; veri canli guncellendiginde
/// mevcut degerden yeni degere animasyonlu gecer.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.loading,
    this.decimals = 0,
    this.suffix = '',
  });

  final double value;
  final String label;
  final bool loading;
  final int decimals;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.primary,
              ),
            )
          else
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (_, animated, __) => Text(
                '${animated.toStringAsFixed(decimals)}$suffix',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                  height: 1.1,
                ),
              ),
            ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  height: 1.25,
                ),
          ),
        ],
      ),
    );
  }
}

/// Kompakt moddaki tek satirlik istatistik parcasi
class _CompactStat extends StatelessWidget {
  const _CompactStat({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
