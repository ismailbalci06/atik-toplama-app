import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/atos_logo.dart';
import '../../data/auth_repository.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_form_bits.dart';
import 'register_screen.dart';

/// Giris ekrani — Hümeyra'nın tasarimina birebir.
///
/// Basarili girişte hicbir yonlendirme yapilmaz: AuthGate oturum akisini
/// dinledigi icin ekran KENDILIGINDEN degisir.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Giris denemesi — hata olursa formun ustunde gosterilir
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    Haptics.action();

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
      // Basarili: AuthGate devreye girer, burada yonlendirme yok.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Beklenmeyen bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Google ile giris — basarili olursa AuthGate ekrani degistirir
  Future<void> _googleSignIn() async {
    Haptics.action();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Google ile giriş tamamlanamadı.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sifre sifirlama — e-posta alani doluysa gonderir
  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error =
          'Şifre sıfırlama için önce e-posta adresinizi yazın.');
      return;
    }
    Haptics.tap();
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (!mounted) return;
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Şifre sıfırlama bağlantısı $email adresine gönderildi.')),
      );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Logo ---
                    const Center(child: AtosLogo(height: 66)),
                    const SizedBox(height: 34),

                    // --- Baslik ---
                    Text('Hoş geldiniz', style: text.headlineSmall),
                    const SizedBox(height: 4),
                    Text('Hesabınıza giriş yapın', style: text.bodySmall),
                    const SizedBox(height: 24),

                    // --- Hata kutusu ---
                    if (_error != null) ...[
                      AuthErrorBox(message: _error!),
                      const SizedBox(height: 14),
                    ],

                    // --- E-posta ---
                    const FieldLabel('E-POSTA'),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        hintText: 'ornek@sirket.com',
                        prefixIcon: Icon(Icons.mail_outline, size: 20),
                      ),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'E-posta adresinizi girin';
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Geçerli bir e-posta adresi girin';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // --- Sifre ---
                    const FieldLabel('ŞİFRE'),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v ?? '').isEmpty
                          ? 'Şifrenizi girin'
                          : null,
                    ),

                    // --- Sifremi unuttum ---
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _forgotPassword,
                        child: const Text('Şifremi Unuttum'),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // --- Giris butonu (tasarimda LACIVERT) ---
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.night,
                          disabledBackgroundColor:
                              AppColors.night.withOpacity(0.5),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Giriş'),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // --- "veya" ayraci ---
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('veya', style: text.bodySmall),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // --- Google ile devam et ---
                    GoogleSignInButton(
                      onPressed: _busy ? null : _googleSignIn,
                    ),
                    const SizedBox(height: 12),

                    // --- Hesap olustur ---
                    SizedBox(
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                Haptics.tap();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const RegisterScreen(),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('Hesap Oluştur'),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Center(
                      child: Text(
                        '© 2026 ATOS · Türkiye',
                        style: text.bodySmall?.copyWith(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
