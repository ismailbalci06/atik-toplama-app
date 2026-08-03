import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/reward_models.dart';
import '../providers/rewards_providers.dart';

/// OPERATOR PANELI — onay bekleyen odul taleplerinin karara baglandigi ekran.
///
/// YETKI: Bu ekrani yalnizca `admins/{uid}` kaydi olan kullanicilar acabilir.
/// Ama asil koruma burada DEGIL: Firestore kurallari, operator olmayan birinin
/// tum talepleri okumasini ve durum guncellemesini reddeder. Bu ekran sadece
/// arayuzu gosterir/gizler.
///
/// Operator bir talebi onaylarken kullanicinin bakiyesini de gorur; bakiye
/// hesabi kullanicinin kendi ekranindakiyle AYNI fonksiyondan gelir
/// (PointsWallet.compute), yani iki taraf ayni sayiyi konusur.
class OperatorScreen extends ConsumerWidget {
  const OperatorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingRedemptionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Operatör Paneli')),
      body: pendingAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => _ErrorBox(message: readableError(e)),
        data: (pending) {
          if (pending.isEmpty) return const _EmptyQueue();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Onay bekleyen talepler',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusBadge),
                    ),
                    child: Text(
                      '${pending.length}',
                      style: const TextStyle(
                        color: AppColors.warningInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'En eski talep başta. Karar verilen talep listeden düşer.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ...pending.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PendingCard(redemption: r),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Tek bir bekleyen talep — kullanici, odul, puan ve BAKIYE gosterimi.
class _PendingCard extends ConsumerStatefulWidget {
  const _PendingCard({required this.redemption});

  final Redemption redemption;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  bool _busy = false;

  Future<void> _decide(bool approve) async {
    final r = widget.redemption;
    Haptics.tap();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Talep onaylansın mı?' : 'Talep reddedilsin mi?'),
        content: Text(
          approve
              ? '${r.displayName} · ${r.rewardTitle} (${r.costPoints} puan) '
                  'onaylanacak. Bu karar geri alınamaz.'
              : '${r.displayName} · ${r.rewardTitle} talebi reddedilecek. '
                  'Puanlar kullanıcının bakiyesine geri döner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: approve ? AppColors.primary : AppColors.error,
            ),
            child: Text(approve ? 'Onayla' : 'Reddet'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(rewardsRepositoryProvider).decideRedemption(
            redemptionId: r.id,
            approve: approve,
            operatorId: ref.read(currentUserIdProvider),
          );
      // Kayit 'beklemede' olmaktan cikinca listeden kendiliginden duser;
      // burada elle bir sey silmiyoruz (tek gercek kaynak Firestore).
      if (mounted) {
        Haptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'Talep onaylandı.' : 'Talep reddedildi.'),
            backgroundColor:
                approve ? AppColors.primary : AppColors.neutralInk,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      final message = logAndReadError(e, context: 'decideRedemption');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İşlem tamamlanamadı: $message'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.redemption;
    final wallet = ref.watch(walletOfUserProvider(r.userId));
    final sufficient = wallet.balance >= 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- Kullanici + odul ---
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(wallet.tier.emoji,
                    style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text('${r.rewardTitle} · ${r.costPoints} puan',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // --- Bakiye ozeti: karari veren kisi rakami gorsun ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  sufficient
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  size: 17,
                  color: sufficient ? AppColors.successInk : AppColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sufficient
                        ? 'Kazanılan ${wallet.earned} · ayrılan ${wallet.spent} '
                            '· kalan ${wallet.balance} puan'
                        : 'DİKKAT: bu talep bakiyeyi aşıyor '
                            '(kalan ${wallet.balance} puan)',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight:
                          sufficient ? FontWeight.w500 : FontWeight.w700,
                      color: sufficient
                          ? AppColors.textSecondary
                          : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- Karar butonlari ---
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: AppColors.primary),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _decide(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Reddet'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _decide(true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Onayla'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Kuyruk bosken
class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.successBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inbox_rounded,
                  size: 30, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 14),
            Text('Bekleyen talep yok',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Kullanıcılar ödül talep ettiğinde burada anında görünür.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Yetkisiz erisim dahil tum hata durumlari
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 34, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text('Talepler görüntülenemedi',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              // Yetkisiz kullanicida burasi permission-denied gosterir:
              // koruma arayuzde degil sunucuda oldugu icin bu BEKLENEN
              // davranistir.
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
