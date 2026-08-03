import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/atos_logo.dart';
import '../../../../core/widgets/scope_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../impact/domain/impact_stats.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';
import '../../../waste_request/presentation/providers/waste_request_providers.dart';
import '../../../waste_request/presentation/screens/request_tracking_screen.dart';
import '../../../waste_request/presentation/screens/user_map_screen.dart';
import '../../../waste_request/presentation/widgets/request_tile.dart';

/// Ana Sayfa — Hümeyra'nın dashboard tasarimi.
///
/// TUM rakamlar GERCEK: kullanicinin kendi Firestore talepleri uzerinden
/// hesaplanir (sahte veri yok). Hic talep yoksa sayilar 0 gorunur ve
/// liste bos durum mesaji gosterir.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final name = ref.watch(currentUserNameProvider);
    final userId = ref.watch(currentUserIdProvider);
    final requestsAsync = ref.watch(userRequestsProvider(userId));

    final requests = requestsAsync.valueOrNull ?? const <WasteRequest>[];
    final loading = requestsAsync.isLoading;

    // --- Gercek veriden turetilen ozetler ---
    // Aktif talepler: liste (en yenisi basta) — hem sayac hem "devam et"
    // kisayolu ayni kaynagi kullanir.
    final activeRequests =
        requests.where((r) => r.status.isActive).toList();
    final active = activeRequests.length;

    final completed =
        requests.where((r) => r.status == RequestStatus.tamamlandi).toList();
    final impact = ImpactStats.fromRequests(completed);

    final now = DateTime.now();
    final thisMonth = requests
        .where((r) =>
            r.createdAt.year == now.year && r.createdAt.month == now.month)
        .length;

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async => ref.invalidate(userRequestsProvider(userId)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            // --- Ust bar: logo + cikis ---
            Row(
              children: [
                const AtosLogo(height: 30),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _confirmSignOut(context, ref),
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text('Çıkış'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // --- Karsilama ---
            Text('Merhaba, $name 👋', style: text.headlineSmall),
            const SizedBox(height: 4),
            if (loading || active == 0)
              Text(
                loading
                    ? 'Talepleriniz yükleniyor…'
                    : 'Şu an aktif talebiniz yok.',
                style: text.bodySmall,
              )
            else
              // Aktif talep varsa bu satir CANLI TAKIBE kisayoldur:
              // takip ekranindan cikan kullanici talebine buradan doner.
              _ActiveRequestLink(
                count: active,
                onTap: () => openTracking(context, activeRequests.first),
              ),
            const SizedBox(height: 20),

            // --- Kisisel etki basligi ---
            // KAPSAM UYARISI: asagidaki 3 kart SADECE bu kullanicinin
            // talepleridir. Rol Secim ekranindaki pano ise sistem geneli;
            // rakamlar tutmaz, bu yuzden kapsam ekranda yaziyor.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tesisinizin Çevresel Etkisi',
                    style: text.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                ScopeBadge.personal(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Yalnızca sizin taleplerinizden hesaplanır',
              style: text.bodySmall,
            ),
            const SizedBox(height: 10),

            // --- 3'lu istatistik kartlari (gercek veri) ---
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    value: requests.length.toDouble(),
                    label: 'Toplam\nTalep',
                    loading: loading,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    value: impact.wasteKg,
                    suffix: ' kg',
                    label: 'Kurtarılan\nAtık',
                    loading: loading,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    value: impact.co2Kg,
                    suffix: ' kg',
                    label: 'Önlenen\nCO₂',
                    loading: loading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // --- Ana aksiyon: yesil gradyan buton ---
            _CreateRequestButton(
              onTap: () {
                Haptics.action();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UserMapScreen()),
                );
              },
            ),
            const SizedBox(height: 22),

            // --- Son Talepler basligi + bu ay rozeti ---
            Row(
              children: [
                Text('Son Talepler', style: text.titleMedium),
                const Spacer(),
                if (thisMonth > 0)
                  Row(
                    children: [
                      const Icon(Icons.trending_up_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        '+$thisMonth bu ay',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // --- Son 3 talep ---
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (requests.isEmpty)
              const _EmptyRequests()
            else
              ...requests.take(3).map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RequestTile(
                        request: r,
                        // Aktif talep -> canli takip; gecmis talep -> pasif
                        onTap: r.status.isActive
                            ? () => openTracking(context, r)
                            : null,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  /// Cikis onayi — yanlislikla oturum kapatilmasin
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    Haptics.tap();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Çıkış yapılsın mı?'),
        content: const Text('Hesabınızdan çıkış yapmak üzeresiniz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Çıkış yap'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      // Oturumu kapat + provider onbelleklerini temizle + yigini bosalt
      await signOutAndReset(context, ref);
    }
  }
}

/// "Bugün N aktif talebiniz var" satiri — canli takibe kisayol.
///
/// Gorsel olarak karsilama metninin devami gibi durur (ayni bodySmall
/// tipografisi), ama yesil renk + ok ile tiklanabilir oldugunu soyler.
class _ActiveRequestLink extends StatelessWidget {
  const _ActiveRequestLink({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                count == 1
                    ? 'Bugün 1 aktif talebiniz var · takibe dön'
                    : 'Bugün $count aktif talebiniz var · takibe dön',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right,
                size: 16, color: AppColors.primaryDark),
          ],
        ),
      ),
    );
  }
}

/// Tasarimdaki genis yesil "+ Talep Oluştur" butonu
class _CreateRequestButton extends StatelessWidget {
  const _CreateRequestButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusButton),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            gradient: AppColors.energyGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.28),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text(
                  'Talep Oluştur',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashboard istatistik karti
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.loading,
    this.suffix = '',
  });

  final double value;
  final String label;
  final bool loading;
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
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, animated, __) => Text(
                '${animated.toStringAsFixed(0)}$suffix',
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

/// Hic talep yokken Son Talepler bolumu
class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined,
              size: 28, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text(
            'Henüz talep oluşturmadınız',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Yukarıdaki butondan ilk toplama talebinizi oluşturun.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
