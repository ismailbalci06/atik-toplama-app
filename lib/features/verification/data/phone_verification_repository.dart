import 'package:firebase_auth/firebase_auth.dart';

/// Telefon dogrulama (Firebase Phone Auth) erisim katmani.
///
/// IZOLE: Mevcut [AuthRepository] dosyasina HIC dokunulmadi. Giris, kayit,
/// sifre sifirlama ve cikis akislari bu modulden tamamen habersizdir —
/// yani buradaki bir hata oturum akisini kiramaz.
///
/// NE YAPAR: Oturum ACIK olan kullanicinin hesabina telefon numarasi
/// BAGLAR (link). Yeni bir hesap acmaz, mevcut hesabi degistirmez;
/// yalnizca dogrulanmis bir telefon ekler. Basarili olursa numara
/// Firebase tarafinda `user.phoneNumber` alanina yazilir — yani
/// "dogrulanmis" rozeti bizim uydurdugumuz bir bayrak degil, kimlik
/// saglayicisinin kaydidir.
///
/// PLATFORM NOTU: `linkWithPhoneNumber` Flutter'da WEB icindir (reCAPTCHA
/// tabanli akis). Uygulama web'de yayinlandigi icin hedefimiz budur;
/// mobil derlemede cagrilirsa anlasilir bir hata mesajina donusur.
class PhoneVerificationRepository {
  PhoneVerificationRepository({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Oturumdaki hesaba telefon baglama akisini BASLATIR.
  ///
  /// [e164Phone] +905321234567 bicimindedir (bkz. TrPhone.normalize).
  /// Donen [ConfirmationResult] ile SMS kodu dogrulanir.
  ///
  /// reCAPTCHA dogrulayicisini bilincli olarak biz olusturmuyoruz:
  /// paket, verilmediginde gorunmez bir dogrulayici olusturup islem
  /// bitince temizliyor. Elle yonetmek, ekran kapanirsa sayfada
  /// artik bir reCAPTCHA konteyneri birakma riski tasir.
  Future<ConfirmationResult> startVerification(String e164Phone) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Telefon doğrulaması için önce giriş yapmalısınız.');
    }
    return user.linkWithPhoneNumber(e164Phone);
  }

  /// SMS kodunu dogrular ve numarayi hesaba baglar.
  Future<void> confirmCode(
    ConfirmationResult confirmation,
    String smsCode,
  ) async {
    await confirmation.confirm(smsCode);
    // Baglama sonrasi yerel kullaniciyi tazele ki phoneNumber alani
    // aninda okunabilsin.
    await _auth.currentUser?.reload();
  }

  /// Oturumdaki hesabin DOGRULANMIS numarasi (yoksa null).
  ///
  /// Bu deger bizim tuttugumuz bir alan degil, Firebase Auth'un kendi
  /// kaydidir — uygulamadan yazilamaz, dolayisiyla sahtelenemez.
  Stream<String?> watchVerifiedPhone() =>
      _auth.userChanges().map((u) => u?.phoneNumber);

  /// Anlik deger (ekran ilk acildiginda beklemeden gostermek icin).
  String? get currentVerifiedPhone => _auth.currentUser?.phoneNumber;
}

/// Phone Auth hata kodlarini TURKCE ve EYLEME DONUK mesajlara cevirir.
///
/// Ham Firebase mesajlari ("invalid-verification-code") kullaniciya
/// hicbir sey anlatmaz. Ozellikle `operation-not-allowed` onemlidir:
/// bu, Console'da Phone saglayicisinin acilmadigi anlamina gelir ve
/// kurulum sirasinda en sik karsilasilan hatadir.
String phoneAuthMessage(Object error) {
  if (error is StateError) return error.message;
  if (error is! FirebaseAuthException) {
    final raw = error.toString();
    // Web disi platformda link akisi desteklenmez
    if (raw.contains('UnimplementedError') || raw.contains('not implemented')) {
      return 'Telefon doğrulama şu an yalnızca web sürümünde çalışıyor.';
    }
    return raw.replaceFirst('Exception: ', '');
  }

  switch (error.code) {
    case 'invalid-phone-number':
      return 'Telefon numarası geçersiz görünüyor. Numarayı kontrol edin.';
    case 'invalid-verification-code':
      return 'Doğrulama kodu hatalı. Kodu tekrar girin.';
    case 'code-expired':
    case 'session-expired':
      return 'Kodun süresi doldu. Yeni kod isteyin.';
    case 'too-many-requests':
      return 'Çok fazla deneme yapıldı. Bir süre sonra tekrar deneyin.';
    case 'credential-already-in-use':
    case 'account-exists-with-different-credential':
      return 'Bu numara başka bir hesaba bağlı. Farklı bir numara deneyin.';
    case 'provider-already-linked':
      return 'Bu hesapta zaten doğrulanmış bir telefon numarası var.';
    case 'operation-not-allowed':
      return 'Telefon doğrulama bu projede etkin değil. '
          'Firebase Console → Authentication → Sign-in method → Phone '
          'sağlayıcısı açılmalı.';
    case 'captcha-check-failed':
      return 'Güvenlik doğrulaması tamamlanamadı. Sayfayı yenileyip '
          'tekrar deneyin.';
    case 'quota-exceeded':
      return 'SMS kotası doldu. Daha sonra tekrar deneyin.';
    case 'requires-recent-login':
      return 'Güvenlik için tekrar giriş yapmanız gerekiyor.';
    default:
      return '[${error.code}] ${error.message ?? "Bilinmeyen hata"}';
  }
}
