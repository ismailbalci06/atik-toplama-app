import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Kimlik dogrulama erisim katmani.
///
/// TUM Firebase Auth islemleri buradan gecer — ekranlar asla dogrudan
/// FirebaseAuth'a dokunmaz. Boylece hata mesajlari tek yerden Turkcelestirilir
/// ve ileride saglayici degisse (Google, SMS) sadece bu dosya guncellenir.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Oturum durumu akisi — giris/cikis oldugunda aninda yayin yapar
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Su anki kullanici (oturum yoksa null)
  User? get currentUser => _auth.currentUser;

  /// E-posta ve sifre ile giris
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      _log('signIn', e.code, e.message);
      throw AuthFailure(_messageFor(e.code));
    } catch (e) {
      _log('signIn', 'bilinmeyen', '$e');
      throw AuthFailure('Giriş yapılamadı. Bağlantınızı kontrol edin.');
    }
  }

  /// Yeni hesap olusturur ve goruntulenen adi kaydeder.
  ///
  /// ONEMLI: Ad kaydetme (updateDisplayName) KOZMETIK bir adimdir.
  /// Hesap zaten olusturulduktan sonra bu adim hata verirse kaydi
  /// BASARISIZ saymayiz — aksi halde kullanici "hata" gorur ama hesabi
  /// aslinda olusmustur ve ikinci denemede "bu e-posta zaten kayitli"
  /// hatasina takilir. (Yasanan sorun tam olarak buydu.)
  Future<UserCredential> register({
    required String name,
    required String email,
    required String password,
  }) async {
    late final UserCredential cred;

    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      _log('register', e.code, e.message);
      throw AuthFailure(_messageFor(e.code));
    } catch (e) {
      _log('register', 'bilinmeyen', '$e');
      throw AuthFailure('Kayıt tamamlanamadı. Bağlantınızı kontrol edin.');
    }

    // --- Buradan sonrasi basarisiz olsa bile hesap OLUSMUSTUR ---
    try {
      await cred.user?.updateDisplayName(name.trim());
      await cred.user?.reload();
    } catch (e) {
      // Sessizce gec: kullanici yine de giris yapmis olur, adi e-postadan
      // turetilir. Konsola not dusuyoruz ki gelistirici gorebilsin.
      _log('updateDisplayName', 'yok sayildi', '$e');
    }

    return cred;
  }

  /// Google hesabiyla giris.
  ///
  /// Web'de acilir pencere (popup) akisi kullanilir — ayri bir paket
  /// gerekmez, firebase_auth_web bunu dogrudan destekler.
  /// Mobilde ayni saglayici `signInWithProvider` ile calisir.
  ///
  /// Hesap yoksa Firebase otomatik olusturur; ad ve e-posta Google'dan
  /// geldigi icin ayrica displayName yazmaya gerek yoktur.
  Future<UserCredential> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..setCustomParameters({'prompt': 'select_account'});

    try {
      if (kIsWeb) {
        return await _auth.signInWithPopup(provider);
      }
      return await _auth.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      _log('signInWithGoogle', e.code, e.message);
      throw AuthFailure(_messageFor(e.code));
    } catch (e) {
      _log('signInWithGoogle', 'bilinmeyen', '$e');
      throw AuthFailure('Google ile giriş tamamlanamadı.');
    }
  }

  /// Sifre sifirlama e-postasi gonderir
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      _log('sendPasswordReset', e.code, e.message);
      throw AuthFailure(_messageFor(e.code));
    }
  }

  /// Oturumu kapatir
  Future<void> signOut() => _auth.signOut();

  /// Gelistirici konsoluna ayrintili kayit (kullaniciya gosterilmez)
  void _log(String op, String code, String? message) {
    debugPrint('🔐 Auth[$op] kod="$code" mesaj="${message ?? ''}"');
  }

  /// Firebase hata kodlarini KULLANICI DILINE cevirir.
  ///
  /// Kodlar iki bicimde gelebiliyor:
  ///   • SDK bicimi   : `email-already-in-use`
  ///   • Ham API bicimi: `EMAIL_EXISTS`  (Flutter Web'de bazen boyle geliyor)
  /// Ikisini de karsilamak icin kodu once normallestiriyoruz.
  String _messageFor(String rawCode) {
    final code = rawCode.toLowerCase().replaceAll('_', '-');

    switch (code) {
      case 'invalid-email':
        return 'Geçersiz e-posta adresi.';

      case 'user-disabled':
      case 'user-disabled-error':
        return 'Bu hesap devre dışı bırakılmış.';

      case 'user-not-found':
      case 'email-not-found':
      case 'wrong-password':
      case 'invalid-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'E-posta veya şifre hatalı.';

      case 'email-already-in-use':
      case 'email-exists':
        return 'Bu e-posta ile zaten bir hesap var. Giriş yapmayı deneyin.';

      case 'weak-password':
      case 'password-login-disabled':
        return 'Şifre en az 6 karakter olmalı.';

      case 'network-request-failed':
        return 'İnternet bağlantısı kurulamadı.';

      case 'too-many-requests':
      case 'too-many-attempts-try-later':
        return 'Çok fazla deneme yapıldı. Lütfen biraz bekleyin.';

      case 'operation-not-allowed':
        return 'E-posta/şifre girişi Firebase Console\'da etkinleştirilmemiş.';

      case 'unauthorized-domain':
        return 'Bu alan adı Firebase Auth\'ta yetkili değil '
            '(Authentication → Settings → Authorized domains).';

      case 'admin-restricted-operation':
        return 'Yeni kayıt şu an kapalı (Firebase Console → Authentication → '
            'Settings → User actions).';

      // --- Google (popup) akisina ozel durumlar ---
      case 'popup-closed-by-user':
      case 'user-cancelled':
      case 'cancelled-popup-request':
        return 'Google girişi iptal edildi.';

      case 'popup-blocked':
        return 'Tarayıcı açılır pencereyi engelledi. '
            'İzin verip tekrar deneyin.';

      case 'account-exists-with-different-credential':
        return 'Bu e-posta başka bir yöntemle kayıtlı. '
            'E-posta ve şifrenizle giriş yapın.';

      default:
        // Kod ekranda gorunur: bir daha "genel hata" ile kor kalmayiz
        return 'Bir sorun oluştu (kod: $rawCode). Lütfen tekrar deneyin.';
    }
  }
}

/// Ekranlara gosterilebilir, Turkcelestirilmis kimlik dogrulama hatasi
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
