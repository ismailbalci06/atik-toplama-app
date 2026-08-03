import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/atos_logo.dart';
import '../../../../core/widgets/impact_dashboard.dart';
import '../../../../core/widgets/scope_badge.dart';
import '../../../collector/presentation/screens/collector_map_screen.dart';
import '../../../impact/presentation/providers/impact_providers.dart';
import '../../../rewards/presentation/providers/rewards_providers.dart';
import '../../../rewards/presentation/screens/operator_screen.dart';
import '../../../shell/presentation/screens/main_shell.dart';

/// Rol secim ekrani — uygulamanin giris noktasi.
///
/// Gorsel: ATOS kimligi (logo, lacivert+yesil palet, yuvarlak kartlar).
/// Gercek surumde bu ekranin yerini auth sonrasi rol yonlendirmesi alacak.
class RoleSelectScreen extends ConsumerWidget {
  const RoleSelectScreen({super.key});

  /// Panonun kapsamini acikca yazan ibare — Ana Sayfa'daki kisisel
  /// sayaclarla karistirilmasin diye her durumda (yukleniyor/hata dahil)
  /// ayni metin gosterilir.
  static const String _scopeNote =
      'Tüm ATOS kullanıcılarının tamamlanan teslimatları';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // CANLI etki verisi: tamamlanmis teslimatlardan gercek zamanli hesaplanir
    final impact = ref.watch(impactStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 36),

              // --- ATOS logosu ---
              const Center(child: AtosLogo(height: 46, showTagline: true)),
              const SizedBox(height: 26),

              // --- Karsilama ---
              Text(
                'Hoş geldiniz 👋',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Devam etmek için rolünüzü seçin',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),

              // --- Etki Panosu: CANLI, gercek Firestore verisinden ---
              // KAPSAM: burasi SISTEM GENELI. Ana Sayfa'daki 3'lu kart ise
              // yalnizca oturum acan kullanicinin verisi — rakamlarin
              // farkli olmasi normal, bu yuzden kapsam ekranda yaziyor.
              impact.when(
                data: (s) => ImpactDashboard(
                  treesSaved: s.trees,
                  co2PreventedKg: s.co2Kg,
                  wasteRecycledKg: s.wasteKg,
                  deliveries: s.deliveries,
                  scopeBadge: ScopeBadge.global(),
                  scopeNote: _scopeNote,
                ),
                loading: () => ImpactDashboard(
                  loading: true,
                  scopeBadge: ScopeBadge.global(),
                  scopeNote: _scopeNote,
                ),
                error: (_, __) => ImpactDashboard(
                  scopeBadge: ScopeBadge.global(),
                  scopeNote: _scopeNote,
                ),
              ),
              const SizedBox(height: 26),

              // --- Rol kartlari ---
              _RoleCard(
                icon: Icons.storefront_outlined,
                title: 'Atık Üreten (İşletme / Site)',
                subtitle:
                    'Tesisinizde veya sitenizde biriken toplu atık için toplama talebi oluşturun',
                onTap: () => _goTo(context, const MainShell()),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.local_shipping_outlined,
                title: 'Toplayıcı (Görevli)',
                subtitle:
                    'Bölgenizdeki talepleri görün, alın ve rotanızı oluşturun',
                onTap: () => _goTo(context, const CollectorMapScreen()),
              ),

              // --- Operator karti: YALNIZCA yetkili hesapta gorunur ---
              // Yetki `admins/{uid}` dokumanindan gelir. Bu kart sadece
              // arayuzu acar; yetkisiz biri ekrani zorlasa bile Firestore
              // kurallari okuma/yazmayi reddeder.
              ...ref.watch(isAdminProvider).maybeWhen(
                    data: (isAdmin) => isAdmin
                        ? [
                            const SizedBox(height: 12),
                            _RoleCard(
                              icon: Icons.admin_panel_settings_outlined,
                              title: 'Operatör (ATOS Yönetim)',
                              subtitle:
                                  'Ödül taleplerini onaylayın veya reddedin',
                              onTap: () =>
                                  _goTo(context, const OperatorScreen()),
                            ),
                          ]
                        : const <Widget>[],
                    orElse: () => const <Widget>[],
                  ),
            ],
          ),
        ),
      ),
    );
  }

  /// Secilen role ait ekrana gecis yapar (geri tusu ile rol ekranina donulur).
  void _goTo(BuildContext context, Widget screen) {
    Haptics.tap();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

/// Rol secim karti — tasarimdaki liste satiri diliyle ayni:
/// yuvarlak ikon kutusu, baslik, aciklama, sag ok.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.softShadow,
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.primaryDark, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
