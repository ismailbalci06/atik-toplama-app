import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/phone_verification_repository.dart';
import '../../domain/tr_phone.dart';
import '../providers/verification_providers.dart';

/// TELEFON DOGRULAMA — iki adimli akis.
///
/// Adim 1: numara girilir, SMS gonderilir (gorunmez reCAPTCHA calisir)
/// Adim 2: gelen 6 haneli kod girilir, numara hesaba BAGLANIR
///
/// OPSIYONELDIR: giris ve kayit akislarina hic dokunulmaz. Kullanici bu
/// ekrani hic acmasa da uygulamanin tamami calisir. Boylece kimlik
/// katmanini guclendirirken mevcut oturum akisini riske atmiyoruz.
class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  ConsumerState<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState
    extends ConsumerState<PhoneVerificationScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  ConfirmationResult? _confirmation;
  bool _busy = false;
  String? _error;

  /// Adim 2'de gosterilecek numara (maskeli)
  String? _sentTo;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool get _phoneValid => TrPhone.isValid(_phoneController.text);
  bool get _codeValid => _codeController.text.trim().length == 6;

  Future<void> _sendCode() async {
    final e164 = TrPhone.normalize(_phoneController.text);
    if (e164 == null) return;

    Haptics.action();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(phoneVerificationRepositoryProvider)
          .startVerification(e164);
      if (!mounted) return;
      setState(() {
        _confirmation = result;
        _sentTo = TrPhone.mask(e164);
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = phoneAuthMessage(e);
      });
    }
  }

  Future<void> _confirm() async {
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
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Telefon numaranız doğrulandı.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = phoneAuthMessage(e);
      });
    }
  }

  /// Adim 1'e don (numarayi duzeltmek icin)
  void _restart() {
    Haptics.tap();
    setState(() {
      _confirmation = null;
      _sentTo = null;
      _codeController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final step2 = _confirmation != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Telefon Doğrulama')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            step2 ? 'Kodu girin' : 'Numaranızı doğrulayın',
            style: text.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            step2
                ? '$_sentTo numarasına 6 haneli bir kod gönderdik.'
                : 'Doğrulanmış numara, tesisinizin kimliğini güçlendirir ve '
                    'saha görevlisiyle iletişimi kolaylaştırır.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 22),

          if (!step2) ...[
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              autofocus: true,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              inputFormatters: [
                // Rakam, bosluk ve + disini hic kabul etme
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: InputDecoration(
                labelText: 'Cep telefonu',
                hintText: '0532 123 45 67',
                prefixIcon: const Icon(Icons.phone_iphone_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusField),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // SEFFAFLIK: Firebase'e TAM OLARAK ne gonderilecegini gosteriyoruz.
            // Boylece "numara yanlis mi gidiyor?" sorusu bir daha tahmine
            // kalmaz; kullanici bastaki 0'in temizlendigini kendi gorur.
            if (_phoneValid)
              Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 15, color: AppColors.successInk),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Gönderilecek numara: '
                      '${TrPhone.normalize(_phoneController.text)}',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.successInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                'Türkiye cep numarası (5 ile başlar). Ülke kodu ve baştaki '
                '0 otomatik düzenlenir.',
                style: text.bodySmall,
              ),
          ] else ...[
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
              decoration: InputDecoration(
                hintText: '••••••',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusField),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _busy ? null : _restart,
                child: const Text('Numarayı değiştir'),
              ),
            ),
          ],

          // --- Hata kutusu ---
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFCE8E8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 18, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : step2
                      ? (_codeValid ? _confirm : null)
                      : (_phoneValid ? _sendCode : null),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : Text(step2 ? 'Doğrula' : 'Kod Gönder'),
            ),
          ),

          const SizedBox(height: 18),
          // --- Gizlilik bilgilendirmesi ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 15, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Numaranız yalnızca hesabınızı doğrulamak için kullanılır; '
                  'diğer kullanıcılara ve saha görevlilerine gösterilmez.',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
