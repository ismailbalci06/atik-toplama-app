import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/atos_logo.dart';
import '../providers/auth_providers.dart';
import 'login_screen.dart';
import 'role_select_screen.dart';

/// Uygulamanin giris kapisi.
///
/// Oturum akisini dinler ve ekrani KENDILIGINDEN degistirir:
///   • yukleniyor → acilis ekrani
///   • oturum yok → Giris ekrani
///   • oturum var → Rol secimi
///
/// Bu sayede giris/cikis sonrasi hicbir ekranda manuel yonlendirme
/// yazmak gerekmiyor.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    return auth.when(
      loading: () => const _SplashScreen(),
      error: (e, _) => _SplashScreen(error: '$e'),
      data: (user) =>
          user == null ? const LoginScreen() : const RoleSelectScreen(),
    );
  }
}

/// Oturum durumu belirlenene kadar gosterilen acilis ekrani
class _SplashScreen extends StatelessWidget {
  const _SplashScreen({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AtosLogo(height: 62),
            const SizedBox(height: 26),
            if (error == null)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.primary,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Bağlantı kurulamadı.\n$error',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
