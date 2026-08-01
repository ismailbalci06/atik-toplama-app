import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/atos_logo.dart';
import '../../data/auth_repository.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_form_bits.dart';

/// Kayit Ol ekrani — Giris ekraniyla ayni gorsel dil.
///
/// Basarili kayitta Firebase otomatik oturum acar; AuthGate devreye girer
/// ve kullanici uygulamaya duser. Burada manuel yonlendirme yok.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _password2Controller = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _password2Controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    Haptics.action();

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authRepositoryProvider).register(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
          );
      // Kayit sonrasi Firebase oturumu acar -> AuthGate ekrani degistirir.
      // Giris ekranindan buraya push edildigimiz icin yigini temizliyoruz.
      if (mounted) Navigator.of(context).pop();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Beklenmeyen bir hata oluştu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Google ile kayit/giris — Firebase hesabi yoksa otomatik olusturur
  Future<void> _googleSignIn() async {
    Haptics.action();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      if (mounted) Navigator.of(context).maybePop();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Google ile giriş tamamlanamadı.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AtosLogo(height: 54)),
                    const SizedBox(height: 26),

                    Text('Hesap oluşturun', style: text.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'İşletmeniz veya siteniz için ATOS hesabı açın',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 22),

                    if (_error != null) ...[
                      AuthErrorBox(message: _error!),
                      const SizedBox(height: 14),
                    ],

                    // --- Ad Soyad ---
                    const FieldLabel('AD SOYAD'),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Adınız Soyadınız',
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                      ),
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'Adınızı girin'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // --- E-posta ---
                    const FieldLabel('E-POSTA'),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
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
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: 'En az 6 karakter',
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
                      validator: (v) => (v ?? '').length < 6
                          ? 'Şifre en az 6 karakter olmalı'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // --- Sifre tekrar ---
                    const FieldLabel('ŞİFRE TEKRAR'),
                    TextFormField(
                      controller: _password2Controller,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        hintText: 'Şifrenizi tekrar girin',
                        prefixIcon: Icon(Icons.lock_outline, size: 20),
                      ),
                      validator: (v) => v != _passwordController.text
                          ? 'Şifreler eşleşmiyor'
                          : null,
                    ),
                    const SizedBox(height: 24),

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
                            : const Text('Hesap Oluştur'),
                      ),
                    ),
                    const SizedBox(height: 16),

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
                    const SizedBox(height: 16),

                    GoogleSignInButton(
                      onPressed: _busy ? null : _googleSignIn,
                      label: 'Google ile kaydol',
                    ),
                    const SizedBox(height: 10),

                    Center(
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).maybePop(),
                        child: const Text('Zaten hesabım var · Giriş yap'),
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
