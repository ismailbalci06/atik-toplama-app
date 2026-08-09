// TELEFON DOGRULAMA — numara normalizasyonu ve ekran davranisi.
//
// Numara normalizasyonu saf bir fonksiyondur (Firebase'e dokunmaz), bu
// yuzden sinir vakalari burada eksiksiz sinanabilir. "Numaram gecerli ama
// kabul etmiyor" tipi sikayetlerin kaynagi hep bu katmandir.
import 'package:atik_toplama_app/features/verification/data/phone_verification_repository.dart';
import 'package:atik_toplama_app/features/verification/domain/tr_phone.dart';
import 'package:atik_toplama_app/features/verification/presentation/screens/phone_verification_screen.dart';
import 'package:atik_toplama_app/features/auth/presentation/screens/register_screen.dart';
import 'package:atik_toplama_app/features/verification/data/signup_with_phone_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _signupTests();

  group('TrPhone.normalize — kullanicinin yazdigi her bicim', () {
    const beklenen = '+905321234567';

    test('bosluklu, sifirli: "0532 123 45 67"', () {
      expect(TrPhone.normalize('0532 123 45 67'), beklenen);
    });

    test('bitisik, sifirli: "05321234567"', () {
      expect(TrPhone.normalize('05321234567'), beklenen);
    });

    test('sifirsiz: "532 123 45 67"', () {
      expect(TrPhone.normalize('532 123 45 67'), beklenen);
    });

    test('ulke koduyla: "+90 532 123 45 67"', () {
      expect(TrPhone.normalize('+90 532 123 45 67'), beklenen);
    });

    test('ulke kodu artisiz: "905321234567"', () {
      expect(TrPhone.normalize('905321234567'), beklenen);
    });

    test('tireli/parantezli: "(0532) 123-45-67"', () {
      expect(TrPhone.normalize('(0532) 123-45-67'), beklenen);
    });
  });

  group('TrPhone.normalize — GECERSIZ girdiler reddedilir', () {
    test('bos metin', () => expect(TrPhone.normalize(''), isNull));
    test('harf', () => expect(TrPhone.normalize('telefon'), isNull));

    test('eksik hane', () {
      expect(TrPhone.normalize('0532 123 45'), isNull);
    });

    test('fazla hane', () {
      expect(TrPhone.normalize('0532 123 45 67 89'), isNull);
    });

    test('sabit hat (5 ile baslamiyor)', () {
      // Turkiye cep hatlari daima 5 ile baslar
      expect(TrPhone.normalize('0212 123 45 67'), isNull);
      expect(TrPhone.normalize('0312 123 45 67'), isNull);
    });
  });

  group('TrPhone.mask — numara tam gosterilmez', () {
    test('yalnizca son iki hane gorunur', () {
      final masked = TrPhone.mask('+905321234567');
      expect(masked, contains('67'));
      expect(masked, isNot(contains('5321234')),
          reason: 'numaranin govdesi ekranda durmamali');
      expect(masked, contains('•'));
    });
  });

  group('TrPhone.pretty', () {
    test('okunakli bicime cevirir', () {
      expect(TrPhone.pretty('+905321234567'), '0532 123 45 67');
    });
  });

  group('Hata mesajlari TURKCE ve eyleme donuk', () {
    test('Console kurulumu eksikse ne yapilacagi yazar', () {
      final msg = phoneAuthMessage(
        FirebaseAuthException(code: 'operation-not-allowed'),
      );
      expect(msg, contains('Console'));
      expect(msg, contains('Phone'));
      // Firebase ayni kodu bolge politikasi icin de kullaniyor —
      // ikisi de yazmali, yoksa yanlis yere bakilir (bir kez yasandi).
      expect(msg, contains('SMS region policy'));
    });

    test('kod hatasi anlasilir', () {
      final msg = phoneAuthMessage(
        FirebaseAuthException(code: 'invalid-verification-code'),
      );
      expect(msg, contains('kod'));
      // Anlasilir aciklama ONDE, ham Firebase kodu ARKADA olmali:
      // teshis bir daha gizlenmesin diye ikisi birlikte gosteriliyor.
      expect(msg.indexOf('Doğrulama kodu hatalı'),
          lessThan(msg.indexOf('invalid-verification-code')));
    });

    test('numara baskasina bagliysa aciklanir', () {
      final msg = phoneAuthMessage(
        FirebaseAuthException(code: 'credential-already-in-use'),
      );
      expect(msg, contains('başka bir hesaba'));
    });

    test('bilinmeyen kod ham haliyle GOSTERILIR (sessizce yutulmaz)', () {
      final msg = phoneAuthMessage(
        FirebaseAuthException(code: 'beklenmedik-kod', message: 'detay'),
      );
      expect(msg, contains('beklenmedik-kod'));
    });


    test('faturalandirma hatasi ne yapilacagini soyler', () {
      // Gercek numaraya SMS Blaze plani ister; test numarasi istemez.
      // Canlida bu kod alindi, mesaj eyleme donuk olmali.
      final msg = phoneAuthMessage(
        FirebaseAuthException(code: 'billing-not-enabled'),
      );
      expect(msg, contains('Blaze'));
      expect(msg, contains('Phone numbers for testing'));
      expect(msg, contains('billing-not-enabled'), reason: 'ham kod da gorunmeli');
    });

    test('oturum yoksa anlasilir uyari', () {
      final msg = phoneAuthMessage(StateError('önce giriş yapmalısınız.'));
      expect(msg, contains('giriş'));
    });
  });

  group('Dogrulama ekrani', () {
    Widget host() => const ProviderScope(
          child: MaterialApp(home: PhoneVerificationScreen()),
        );

    testWidgets('gecersiz numarada "Kod Gönder" KAPALI', (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(host());
      await t.pump();

      // Bos halde kapali olmali
      var button = t.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);

      // Eksik haneli numara da acmamali
      await t.enterText(find.byType(TextField), '0532 123');
      await t.pump();
      button = t.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('gecerli numarada buton ACILIR', (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(host());
      await t.pump();

      await t.enterText(find.byType(TextField), '0532 123 45 67');
      await t.pump();

      final button = t.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('numara ekranda MASKELENECEGI bilgisi ve gizlilik notu var',
        (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(host());
      await t.pump();

      expect(find.textContaining('diğer kullanıcılara'), findsOneWidget);
    });
  });
}

// =====================================================================
// KAYIT AKISI — telefon zorunlulugu ve sira/geri alma
// =====================================================================
void _signupTests() {
  group('Kayit ekrani — telefon ZORUNLU', () {
    Widget host() => const ProviderScope(
          child: MaterialApp(home: RegisterScreen()),
        );

    testWidgets('formda cep telefonu alani var', (t) async {
      t.view.physicalSize = const Size(430, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(host());
      await t.pump();

      expect(find.text('CEP TELEFONU'), findsOneWidget);
      expect(find.text('0532 123 45 67'), findsOneWidget); // ipucu metni
    });

    testWidgets('gecersiz numarada form dogrulamasi UYARIR', (t) async {
      t.view.physicalSize = const Size(430, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(host());
      await t.pump();

      // Sabit hat girip gonderelim
      await t.enterText(
          find.widgetWithText(TextFormField, '0532 123 45 67'), '0212 123 45 67');
      await t.pump();
      await t.tap(find.text('Hesap Oluştur'));
      await t.pump();

      expect(find.textContaining('5 ile başlar'), findsOneWidget);
    });

    testWidgets('gecerli numarada "Doğrulanacak: +90..." gorunur', (t) async {
      t.view.physicalSize = const Size(430, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(host());
      await t.pump();

      await t.enterText(
          find.widgetWithText(TextFormField, '0532 123 45 67'), '0532 123 45 67');
      await t.pump();

      // Firebase'e TAM OLARAK ne gidecegi ekranda yaziyor
      expect(find.textContaining('+905321234567'), findsOneWidget);
    });
  });

  group('Kayit sirasi ve geri alma sozlesmesi', () {
    test('kod adiminda vazgecilirse hesap SILINMEZ', () {
      // Gecerli bir hesap vardir; telefon Profil'den sonra dogrulanabilir.
      // Calisan hesabi vazgecme yuzunden yok etmek daha buyuk risk olurdu.
      expect(SignUpWithPhoneRepository().keepsAccountOnAbandon, isTrue);
    });
  });
}
