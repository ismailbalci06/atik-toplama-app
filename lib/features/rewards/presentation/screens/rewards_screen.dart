import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/widgets/premium_progress_bar.dart';
import '../../../../core/widgets/scope_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/green_points.dart';
import '../../domain/reward_models.dart';
import '../providers/rewards_providers.dart';

/// ODUL MARKETI — Yesil Puan cuzdani, tesis seviyesi ve odul katalogu.
///
/// DURUSTLUK NOTLARI (juri sorabilir):
/// • Puan, onaylanmis teslimatlardaki GERCEK kilodan dogar; kullanicinin
///   beyani puan uretmez.
/// • Bakiye hicbir yerde saklanmaz, her acilista canli veriden turetilir —
///   yani degistirilebilecek bir "puan" alani yoktur.
/// • Odul talepleri operator onayina duser; otomatik onay Faz 2'dir.
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key, this.embedded = false});

  /// Alt navigasyon kabugu icinde mi calisiyor?
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final wallet = ref.watch(pointsWalletProvider);
    final catalogAsync = ref.watch(rewardCatalogProvider);
    final redemptions =
        ref.watch(userRedemptionsProvider).valueOrNull ?? const <Redemption>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ödül Marketi'),
        automaticallyImplyLeading: !embedded,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          // --- Cuzdan + seviye ---
          _WalletCard(wallet: wallet),
          const SizedBox(height: 18),

          // --- Katalog ---
          Row(
            children: [
              Expanded(child: Text('Ödüller', style: text.titleMedium)),
              const SizedBox(width: 8),
              ScopeBadge.personal('Bakiyenize göre'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Puanınız yettiğinde talep oluşturabilirsiniz.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 10),

          catalogAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
            error: (e, _) => _InfoBox(
              icon: Icons.error_outline,
              title: 'Katalog yüklenemedi',
              body: readableError(e),
            ),
            data: (rewards) {
              if (rewards.isEmpty) {
                return const _InfoBox(
                  icon: Icons.card_giftcard_outlined,
                  title: 'Katalog henüz boş',
                  body: 'Ödüller ATOS ekibi tarafından tanımlanır. '
                      'Tanımlandığı anda burada görünür.',
                );
              }
              return Column(
                children: rewards
                    .map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RewardTile(
                            reward: r,
                            balance: wallet.balance,
                            onRequest: () => _requestReward(context, ref, r),
                          ),
                        ))
                    .toList(),
              );
            },
          ),

          // --- Taleplerim ---
          if (redemptions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Ödül Taleplerim', style: text.titleMedium),
            const SizedBox(height: 10),
            ...redemptions.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RedemptionTile(redemption: r),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Odul talebi olusturur (onay diyalogu ile).
  Future<void> _requestReward(
    BuildContext context,
    WidgetRef ref,
    Reward reward,
  ) async {
    Haptics.tap();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reward.title),
        content: Text(
          '${reward.costPoints} Yeşil Puan karşılığında bu ödülü talep '
          'ediyorsunuz. Talebiniz ATOS ekibinin onayına düşecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Talep et'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(rewardsRepositoryProvider).requestRedemption(
            userId: ref.read(currentUserIdProvider),
            reward: reward,
          );
      if (context.mounted) {
        Haptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ödül talebiniz alındı, onay bekliyor.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      final message = logAndReadError(e, context: 'requestRedemption');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Talep oluşturulamadı: $message'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// Bakiye + tesis seviyesi karti (lacivert marka gradyani)
class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet});

  final PointsWallet wallet;

  @override
  Widget build(BuildContext context) {
    final tier = wallet.tier;
    final next = tier.next;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Yeşil Puan',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Tesis seviyesi rozeti
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
                ),
                child: Text(
                  '${tier.emoji} ${tier.label}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${wallet.balance}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'puan',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            wallet.confirmedDeliveries == 0
                ? 'Onaylanmış teslimatınız olduğunda puan kazanmaya başlarsınız.'
                : '${wallet.confirmedDeliveries} onaylı teslimattan '
                    '${wallet.earned} puan kazandınız'
                    '${wallet.spent > 0 ? " · ${wallet.spent} puan ödüle ayrıldı" : ""}.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),

          // --- Sonraki seviyeye ilerleme ---
          if (next != null) ...[
            const SizedBox(height: 14),
            PremiumProgressBar(value: tier.progressTo(wallet.earned)),
            const SizedBox(height: 6),
            Text(
              '${next.emoji} ${next.label} için '
              '${(next.threshold - wallet.earned).clamp(0, next.threshold)} '
              'puan daha',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Katalogdaki tek odul satiri
class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.reward,
    required this.balance,
    required this.onRequest,
  });

  final Reward reward;
  final int balance;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final affordable = balance >= reward.costPoints;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(reward.emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reward.title,
                    style: Theme.of(context).textTheme.titleSmall),
                if (reward.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(reward.description,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${reward.costPoints} puan',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const Spacer(),
                    // Bakiye yetmiyorsa buton pasif ve NEDEN'i yaziyor
                    if (affordable)
                      ElevatedButton(
                        onPressed: onRequest,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Talep et'),
                      )
                    else
                      Text(
                        '${reward.costPoints - balance} puan eksik',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kullanicinin gecmis odul talebi satiri
class _RedemptionTile extends StatelessWidget {
  const _RedemptionTile({required this.redemption});

  final Redemption redemption;

  @override
  Widget build(BuildContext context) {
    final (bg, ink) = switch (redemption.status) {
      RedemptionStatus.onaylandi => (AppColors.successBg, AppColors.successInk),
      RedemptionStatus.reddedildi => (const Color(0xFFFCE8E8), AppColors.error),
      RedemptionStatus.beklemede => (AppColors.neutralBg, AppColors.neutralInk),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(redemption.rewardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text('${redemption.costPoints} puan',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
            ),
            child: Text(
              redemption.status.label,
              style: TextStyle(
                color: ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bilgi/bos durum kutusu
class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

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
          Icon(icon, size: 28, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
