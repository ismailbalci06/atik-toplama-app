import 'package:firebase_auth/firebase_auth.dart';

/// TELEFON DOGRULAMALI KAYIT — sira ve geri alma mantigi.
///
/// ============================================================
/// NEDEN "once telefon, sonra hesap" DEGIL?
/// ============================================================
/// Istenen sira sunu diyordu: (a) SMS dogrula, (b) e-posta hesabini
/// olustur, (c) telefonu bagla. Firebase'de bu sira TEKNIK OLARAK
/// yetim hesap URETIR:
///
///   • `ConfirmationResult.confirm(kod)` yalnizca kodu dogrulamaz —
///     kullaniciyi TELEFON HESABIYLA OTURUM ACTIRIR. O anda ortada
///     e-postasi olmayan bir hesap olusmustur.
///   • Ardindan `createUserWithEmailAndPassword` cagrilirsa BAMBASKA
///     ikinci bir hesap acilir ve telefon hesabi sahipsiz kalir.
///     Tam da onlenmek istenen "yetim hesap" budur.
///   • SMS kodu tek kullanimliktir; sonradan yeni hesaba baglanamaz.
///
/// ============================================================
/// UYGULANAN SIRA (ayni sonuc, yetim hesap RISKI YOK)
/// ============================================================
///   1. E-posta/sifre ile hesap olustur.
///      -> E-postanin musait olup olmadigi BURADA anlasilir. Kullanimda
///         ise hic SMS gonderilmez; ne kota harcanir ne yarim kayit olur.
///   2. Ayni hesaba telefonu BAGLA (linkWithPhoneNumber -> SMS).
///   3. Kod dogrulaninca numara ayni hesaba islenir.
///
/// Sonuc birebir istenen sey: TEK hesap, hem e-posta hem dogrulanmis
/// telefon; ve `user.phoneNumber` dolu oldugu icin profilde yesil rozet.
///
/// ============================================================
/// GERI ALMA (rollback)
/// ============================================================
/// SMS hic BASLATILAMAZSA (bolge politikasi, kota, saglayici kapali,
/// gecersiz numara) yeni acilmis hesap SILINIR. Boylece kullanici
/// "hesabim var mi yok mu" belirsizliginde kalmaz, ayni e-postayla
/// temiz bir sekilde tekrar deneyebilir.
///
/// SMS gonderildikten SONRA kullanici vazgecerse hesap SILINMEZ:
/// o noktada gecerli bir hesap vardir ve telefonunu Profil ekranindan
/// diledigi zaman dogrulayabilir. Calisan bir hesabi kullanicinin
/// vazgecmesi yuzunden yok etmek, veri kaybi riskini geri almadan
/// daha buyuk yapardi.
class SignUpWithPhoneRepository {
  SignUpWithPhoneRepository({FirebaseAuth? auth}) : _authOverride = auth;

  final FirebaseAuth? _authOverride;

  /// TEMBEL erisim: yapicida FirebaseAuth.instance'a dokunmuyoruz.
  /// Aksi halde sinifi olusturmak bile Firebase'in baslatilmis olmasini
  /// gerektirir ve saf birim testlerinde patlar.
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  /// Adim 2: yeni acilmis hesaba telefon baglamayi baslatir (SMS gonderir).
  ///
  /// Basarisiz olursa hesabi GERI ALIR ve hatayi oldugu gibi yukari
  /// firlatir — cagiran taraf seffaf mesaji gosterir.
  Future<ConfirmationResult> startPhoneLinkOrRollback(String e164Phone) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Kayıt tamamlanamadı: oturum bulunamadı.');
    }

    try {
      return await user.linkWithPhoneNumber(e164Phone);
    } catch (_) {
      // SMS hic baslatilamadi -> yarim kalan hesabi temizle.
      // Silme de basarisiz olursa ASIL hatayi kaybetmemek icin yutuyoruz;
      // kullaniciya gosterilecek olan SMS hatasidir.
      await _safeDeleteCurrentUser();
      rethrow;
    }
  }

  /// Rollback yardimcisi — sessizce dener, asil hatayi golgelemez.
  Future<bool> _safeDeleteCurrentUser() async {
    try {
      await _auth.currentUser?.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Kullanici kod adiminda vazgecerse cagrilir.
  ///
  /// Hesap SILINMEZ (bkz. sinif aciklamasi): gecerli bir hesap vardir,
  /// telefon Profil'den sonra dogrulanabilir.
  bool get keepsAccountOnAbandon => true;
}
