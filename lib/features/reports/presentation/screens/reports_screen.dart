import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/scope_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../impact/domain/impact_stats.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';
import '../../../waste_request/presentation/providers/waste_request_providers.dart';

/// Rapor ekrani.
///
/// ONEMLI: Buradaki hicbir rakam sahte DEGIL. Tum grafikler kullanicinin
/// kendi Firestore taleplerinden hesaplanir:
///   • tur dagilimi  → taleplerdeki atik turleri ve kg'lari
///   • aylik trend   → talebin createdAt alani
///   • etki ozeti    → tamamlanmis teslimatlar (ImpactStats)
/// Veri yoksa uydurma sayi gostermek yerine bos durum mesaji cikar.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final userId = ref.watch(currentUserIdProvider);
    final requestsAsync = ref.watch(userRequestsProvider(userId));

    return SafeArea(
      child: requestsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Rapor yüklenemedi: $e', textAlign: TextAlign.center),
          ),
        ),
        data: (requests) {
          final completed = requests
              .where((r) => r.status == RequestStatus.tamamlandi)
              .toList();
          final impact = ImpactStats.fromRequests(completed);
          final byType = _kgByType(requests);
          final monthly = _monthlyCounts(requests);

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            children: [
              // KAPSAM: bu ekrandaki her rakam KISISELDIR (kullanicinin
              // kendi talepleri). Rol Secim ekranindaki pano sistem geneli.
              Row(
                children: [
                  Expanded(child: Text('Rapor', style: text.headlineSmall)),
                  const SizedBox(width: 8),
                  ScopeBadge.personal(),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Yalnızca sizin talep geçmişinizden hesaplanan çevresel '
                'etki özeti',
                style: text.bodySmall,
              ),
              const SizedBox(height: 20),

              if (requests.isEmpty) ...[
                const _EmptyReport(),
              ] else ...[
                // --- Etki ozeti ---
                _Section(
                  title: 'Tesisinizin Çevresel Etkisi',
                  subtitle: 'Tamamlanan kendi teslimatlarınız',
                  child: Column(
                    children: [
                      _ImpactRow(
                        icon: Icons.recycling_rounded,
                        label: 'Geri kazanılan atık',
                        value: '${impact.wasteKg.toStringAsFixed(0)} kg',
                      ),
                      const SizedBox(height: 12),
                      _ImpactRow(
                        icon: Icons.cloud_off_rounded,
                        label: 'Önlenen karbon salımı',
                        value: '${impact.co2Kg.toStringAsFixed(0)} kg CO₂',
                      ),
                      const SizedBox(height: 12),
                      _ImpactRow(
                        icon: Icons.park_rounded,
                        label: 'Kurtarılan ağaç (kâğıttan)',
                        value: impact.trees.toStringAsFixed(1),
                      ),
                      const SizedBox(height: 12),
                      _ImpactRow(
                        icon: Icons.local_shipping_rounded,
                        label: 'Tamamlanan teslimat',
                        value: '${completed.length}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- Tur bazli dagilim ---
                _Section(
                  title: 'Atık Türü Dağılımı',
                  subtitle: 'Talep ettiğiniz toplam kilogram',
                  child: byType.isEmpty
                      ? const _NoData()
                      : Column(
                          children: byType.entries
                              .map((e) => _TypeBar(
                                    type: e.key,
                                    kg: e.value,
                                    maxKg: byType.values
                                        .reduce((a, b) => a > b ? a : b),
                                  ))
                              .toList(),
                        ),
                ),
                const SizedBox(height: 16),

                // --- Aylik trend ---
                _Section(
                  title: 'Aylık Talep Trendi',
                  subtitle: 'Son 6 ay',
                  child: _MonthlyChart(data: monthly),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Atik turu -> toplam kg. Bir talebin kg'i secili turlere ESIT dagitilir
  /// (model tur basina kg tutmuyor — ImpactStats ile ayni varsayim).
  static Map<WasteType, double> _kgByType(List<WasteRequest> requests) {
    final map = <WasteType, double>{};
    for (final r in requests) {
      if (r.wasteTypes.isEmpty) continue;
      final per = r.estimatedKg / r.wasteTypes.length;
      for (final t in r.wasteTypes) {
        map[t] = (map[t] ?? 0) + per;
      }
    }
    // Buyukten kucuge sirala
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }

  /// Son 6 ayin talep sayilari (eskiden yeniye)
  static List<({String label, int count})> _monthlyCounts(
      List<WasteRequest> requests) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    final now = DateTime.now();
    final out = <({String label, int count})>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final count = requests
          .where((r) =>
              r.createdAt.year == m.year && r.createdAt.month == m.month)
          .length;
      out.add((label: months[m.month - 1], count: count));
    }
    return out;
  }
}

/// Beyaz kart icinde bolum
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Etki ozeti satiri
class _ImpactRow extends StatelessWidget {
  const _ImpactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

/// Tur bazli yatay cubuk
class _TypeBar extends StatelessWidget {
  const _TypeBar({required this.type, required this.kg, required this.maxKg});

  final WasteType type;
  final double kg;
  final double maxKg;

  @override
  Widget build(BuildContext context) {
    final ratio = maxKg <= 0 ? 0.0 : (kg / maxKg).clamp(0.05, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${type.emoji} ${type.label}',
                  style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              Text(
                '${kg.toStringAsFixed(0)} kg',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                children: [
                  Container(height: 9, color: AppColors.surfaceMuted),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: ratio),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => Container(
                      height: 9,
                      width: c.maxWidth * v,
                      decoration: const BoxDecoration(
                        gradient: AppColors.energyGradient,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aylik dikey cubuk grafik
class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.data});

  final List<({String label, int count})> data;

  @override
  Widget build(BuildContext context) {
    final maxCount =
        data.map((e) => e.count).fold<int>(0, (a, b) => a > b ? a : b);

    if (maxCount == 0) return const _NoData();

    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: data.map((e) {
          final ratio = e.count / maxCount;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${e.count}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: e.count == 0
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: ratio),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Container(
                    height: (78 * v).clamp(4, 78),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      gradient: e.count == 0 ? null : AppColors.energyGradient,
                      color: e.count == 0 ? AppColors.surfaceMuted : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(e.label,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Bolumde gosterilecek veri yoksa
class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        'Bu bölüm için henüz yeterli veri yok.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// Hic talep yokken tum rapor ekrani
class _EmptyReport extends StatelessWidget {
  const _EmptyReport();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.bar_chart_rounded,
              size: 34, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text('Henüz rapor oluşmadı',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            'İlk toplama talebinizi oluşturduğunuzda çevresel etki '
            'raporunuz burada otomatik hesaplanmaya başlar.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
