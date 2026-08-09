import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../../verification/data/phone_verification_repository.dart';
import '../../../verification/domain/tr_phone.dart';
import '../../../verification/presentation/providers/verification_providers.dart';
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

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// SMS gonderildiyse dolu olur -> ekran KOD adimina gecer
  ConfirmationResult? _confirmation;

  /// Kod adiminda gosterilecek maskeli numara
  String? _sentTo;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _password2Controller.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// KAYIT — iki asamali, geri alma korumali.
  ///
  /// 1. Hesabi olustur (e-postanin musait oldugu BURADA anlasilir; degilse
  ///    hic SMS gonderilmez, kota harcanmaz, yarim kayit olusmaz).
  /// 2. Ayni hesaba telefonu bagla -> SMS gonder.
  ///    Bu adim hic baslatilamazsa yeni hesap GERI ALINIR (silinir).
  ///
  /// Not: "once SMS, sonra hesap" sirasi Firebase'de yetim hesap uretir —
  /// confirm() kullaniciyi telefon hesabiyla oturum actirir, ardindan
  /// createUser... ikinci bir hesap acar. Gerekce: SignUpWithPhoneRepository.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final e164 = TrPhone.normalize(_phoneController.text);
    if (e164 == null) return;

    FocusScope.of(context).unfocus();
    Haptics.action();
    setState(() {
      _busy = true;
      _error = null;
    });

    // --- Adim 1: hesap ---
    try {
      await ref.read(authRepositoryProvider).register(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
          );
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Beklenmeyen bir hata oluştu.';
        });
      }
      return;
    }

    // --- Adim 2: telefon baglama (basarisiz olursa hesap geri alinir) ---
    try {
      final confirmation = await ref
          .read(signUpWithPhoneRepositoryProvider)
          .startPhoneLinkOrRollback(e164);
      if (!mounted) return;
      setState(() {
        _confirmation = confirmation;
        _sentTo = TrPhone.mask(e164);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${phoneAuthMessage(e)}\n\n'
            'Kaydınız tamamlanmadı ve geri alındı; aynı e-posta ile '
            'tekrar deneyebilirsiniz.';
      });
    }
  }

  /// Kod adimi — numarayi hesaba baglar ve kaydi tamamlar.
  Future<void> _confirmCode() async {
    final confirmation = _confirmation;
    if (confirmation == null) return;

    Haptics.action();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(phoneVerificationRepositoryProvider).confirmCode(
            confirmation,
            _codeController.text.trim(),
          );
      if (!mounted) return;
      Haptics.success();
      // Oturum zaten acik; AuthGate'i serbest birakmak icin yigini bosalt.
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = phoneAuthMessage(e);
      });
    }
  }

  /// Kod adiminda vazgecme — hesap SILINMEZ.
  ///
  /// Bu noktada gecerli bir hesap vardir ve oturum aciktir. Calisan bir
  /// hesabi vazgecme yuzunden yok etmek, geri almanin cozdugu sorundan
  /// daha buyuk bir veri kaybi riski olurdu. Telefon Profil ekranindan
  /// istendigi zaman dogrulanabilir.
  void _skipVerification() {
    Haptics.tap();
    Navigator.of(context).pop();
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

                    // ADIM 2 — SMS gonderildi, kod bekleniyor.
                    // Form alanlari gizlenir; hesap zaten olusmustur.
                    if (_confirmation != null) ...[
                      ..._buildCodeStep(context, text),
                    ] else ...[
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

                    // --- Cep telefonu (ZORUNLU) ---
                    // B2B kurumsal kimlik icin zorunlu. Numara E.164'e
                    // cevrilerek Firebase'e gider; alttaki satir tam olarak
                    // ne gonderilecegini gosterir.
                    const FieldLabel('CEP TELEFONU'),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      decoration: const InputDecoration(
                        hintText: '0532 123 45 67',
                        prefixIcon: Icon(Icons.phone_iphone_rounded, size: 20),
                      ),
                      validator: (v) => TrPhone.isValid(v ?? '')
                          ? null
                          : 'Geçerli bir cep numarası girin (5 ile başlar)',
                    ),
                    if (TrPhone.isValid(_phoneController.text)) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              size: 14, color: AppColors.successInk),
                          const SizedBox(width: 6),
                          Text(
                            'Doğrulanacak: '
                            '${TrPhone.normalize(_phoneController.text)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.successInk,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                    ], // <- adim 1 (form) sonu
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ADIM 2 arayuzu — SMS kodu girisi.
  ///
  /// Hesap bu noktada ZATEN OLUSMUSTUR ve oturum aciktir. Kullanici
  /// vazgecerse hesap silinmez; telefonu Profil'den sonra dogrulayabilir.
  List<Widget> _buildCodeStep(BuildContext context, TextTheme text) {
    return [
      Text('Telefonunuzu doğrulayın', style: text.headlineSmall),
      const SizedBox(height: 4),
      Text(
        'Hesabınız oluşturuldu. $_sentTo numarasına gönderdiğimiz '
        '6 haneli kodu girin.',
        style: text.bodySmall,
      ),
      const SizedBox(height: 22),

      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        autofocus: true,
        enabled: !_busy,
        onChanged: (_) => setState(() {}),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: 8,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: const InputDecoration(
          hintText: '••••••',
          counterText: '',
        ),
      ),
      const SizedBox(height: 20),

      SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: (_busy || _codeController.text.trim().length != 6)
              ? null
              : _confirmCode,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: Colors.white),
                )
              : const Text('Doğrula ve Bitir'),
        ),
      ),
      const SizedBox(height: 6),
      Center(
        child: TextButton(
          onPressed: _busy ? null : _skipVerification,
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: const Text('Daha sonra doğrula'),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hesabınız hazır; şimdi doğrulamazsanız Profil ekranından '
              'istediğiniz zaman doğrulayabilirsiniz.',
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    ];
  }

}
