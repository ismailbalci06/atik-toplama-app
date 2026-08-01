import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';
import '../../../waste_request/presentation/providers/waste_request_providers.dart';

/// Profil ekrani.
///
/// Tum bilgiler GERCEK: ad, e-posta ve uyelik tarihi Firebase Auth'tan,
/// talep sayisi Firestore'dan gelir. Menudeki her aksiyon calisir —
/// bilincli olarak "yakinda" yazan olu satir koymadik.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final userId = ref.watch(currentUserIdProvider);
    final requests =
        ref.watch(userRequestsProvider(userId)).valueOrNull ?? const [];

    final completed =
        requests.where((r) => r.status == RequestStatus.tamamlandi).length;
    final created = user?.metadata.creationTime;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          Text('Profil', style: text.headlineSmall),
          const SizedBox(height: 18),

          // --- Kullanici karti ---
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              boxShadow: AppColors.softShadow,
            ),
            child: Row(
              children: [
                // Bas harfler
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 1.4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(user?.displayName, user?.email),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user?.displayName?.trim().isNotEmpty == true
                            ? user!.displayName!
                            : 'ATOS Kullanıcısı',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user?.email ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // --- Ozet sayilar ---
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  value: '${requests.length}',
                  label: 'Toplam Talep',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  value: '$completed',
                  label: 'Tamamlanan',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  value: created == null
                      ? '—'
                      : '${created.day}.${created.month}.${created.year}',
                  label: 'Üyelik',
                  small: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text('Hesap', style: text.titleMedium),
          const SizedBox(height: 10),

          _MenuCard(
            children: [
              _MenuItem(
                icon: Icons.lock_reset_rounded,
                title: 'Şifre değiştir',
                subtitle: 'E-postanıza sıfırlama bağlantısı gönderilir',
                onTap: () => _resetPassword(context, ref, user?.email),
              ),
              const Divider(height: 1),
              _MenuItem(
                icon: Icons.badge_outlined,
                title: 'Hesap kimliği',
                subtitle: userId.isEmpty
                    ? '—'
                    : '${userId.substring(0, userId.length.clamp(0, 10))}…',
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: 18),

          Text('Uygulama', style: text.titleMedium),
          const SizedBox(height: 10),

          _MenuCard(
            children: [
              _MenuItem(
                icon: Icons.info_outline_rounded,
                title: 'ATOS hakkında',
                subtitle: 'Sürüm 0.1.0 · MVP',
                onTap: () => _showAbout(context),
              ),
              const Divider(height: 1),
              _MenuItem(
                icon: Icons.logout_rounded,
                title: 'Çıkış yap',
                subtitle: 'Hesabınızdan güvenli çıkış',
                danger: true,
                onTap: () => _signOut(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String? name, String? email) {
    final n = (name ?? '').trim();
    if (n.isNotEmpty) {
      final parts = n.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return (parts[0][0] + parts[1][0]).toUpperCase();
      }
      return n.substring(0, 1).toUpperCase();
    }
    final e = (email ?? '').trim();
    return e.isEmpty ? '?' : e.substring(0, 1).toUpperCase();
  }

  Future<void> _resetPassword(
      BuildContext context, WidgetRef ref, String? email) async {
    if (email == null || email.isEmpty) return;
    Haptics.tap();
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sıfırlama bağlantısı $email adresine gönderildi.')),
      );
    } on AuthFailure catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
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
      await signOutAndReset(context, ref);
    }
  }

  void _showAbout(BuildContext context) {
    Haptics.tap();
    showAboutDialog(
      context: context,
      applicationName: 'ATOS',
      applicationVersion: '0.1.0 · MVP',
      applicationLegalese: '© 2026 ATOS · Türkiye',
      children: const [
        SizedBox(height: 12),
        Text(
          'Talep bazlı tersine lojistik sevkiyat platformu. '
          'İşletme ve site yönetimlerinde biriken geri dönüştürülebilir '
          'atıkların en verimli rotayla toplanmasını sağlar.',
        ),
      ],
    );
  }
}

/// Kucuk ozet sayi kutusu
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.value,
    required this.label,
    this.small = false,
  });

  final String value;
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: small ? 13 : 19,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Menu satirlarini saran beyaz kart
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(children: children),
    );
  }
}

/// Tek menu satiri
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.primaryDark;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: danger
              ? AppColors.error.withOpacity(0.09)
              : AppColors.successBg,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: color, size: 19),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: danger ? AppColors.error : null,
            ),
      ),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right,
              size: 20, color: AppColors.textSecondary),
    );
  }
}
