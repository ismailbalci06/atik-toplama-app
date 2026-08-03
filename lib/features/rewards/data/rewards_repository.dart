import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/reward_models.dart';

/// Odul Marketi icin Firestore erisim katmani.
///
/// Projedeki kural burada da gecerli: TUM Firestore erisimi repository'den
/// gecer, UI/provider asla dogrudan FirebaseFirestore'a dokunmaz.
class RewardsRepository {
  RewardsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const _rewardsCollection = 'rewards';
  static const _redemptionsCollection = 'redemptions';
  static const _adminsCollection = 'admins';

  CollectionReference<Map<String, dynamic>> get _rewards =>
      _firestore.collection(_rewardsCollection);

  CollectionReference<Map<String, dynamic>> get _redemptions =>
      _firestore.collection(_redemptionsCollection);

  /// Kullanici OPERATOR mu?
  ///
  /// Yetki, `admins/{uid}` dokumaninin VARLIGINDAN gelir. Bu koleksiyona
  /// uygulamadan yazilamaz (kural: write false) — operator yetkisi yalnizca
  /// Firebase Console'dan, yonetici yetkisiyle verilir. Yani kimse kendini
  /// operator yapamaz.
  Stream<bool> watchIsAdmin(String uid) {
    if (uid.isEmpty) return Stream.value(false);
    return _firestore
        .collection(_adminsCollection)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists)
        // Yetkisi olmayan kullanici kendi admin dokumanini okuyabilir
        // (kural buna izin verir) ama dokuman yoksa false doner.
        .handleError((Object _) => false);
  }

  /// Odul katalogunun canli akisi.
  ///
  /// Siralama istemcide yapilir: `isActive` esitlik filtresi + `costPoints`
  /// siralamasi Firestore'da bilesik indeks gerektirirdi. Katalog kucuk
  /// oldugu icin istemcide siralamak hem yeterli hem indeks bagimliligini
  /// kaldirir. (Ayni gerekce waste_requests sorgularinda da gecerli.)
  Stream<List<Reward>> watchCatalog() {
    return _rewards.snapshots().map((snap) {
      final list = snap.docs
          .map(Reward.fromDoc)
          .where((r) => r.isActive)
          .toList()
        ..sort((a, b) => a.costPoints.compareTo(b.costPoints));
      return list;
    });
  }

  /// Kullanicinin kendi odul taleplerinin canli akisi (en yeni once).
  Stream<List<Redemption>> watchUserRedemptions(String userId) {
    return _redemptions
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Redemption.fromDoc).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Odul talebi olusturur (durum: beklemede).
  ///
  /// Odulun adi ve fiyati kaydin ICINE yazilir: katalog sonradan
  /// degistiginde gecmis talepler carpilmaz.
  ///
  /// NOT: Bakiye yeterliligi burada DOGRULANMAZ — Firestore kurallari
  /// toplam hesabi yapamaz. Arayuz yetersiz bakiyede butonu kapatir,
  /// son onay ise operatordedir (bkz. RedemptionStatus aciklamasi).
  Future<String> requestRedemption({
    required String userId,
    required String userName,
    required Reward reward,
  }) async {
    final doc = await _redemptions.add({
      ...Redemption(
        id: '',
        userId: userId,
        userName: userName,
        rewardId: reward.id,
        rewardTitle: reward.title,
        costPoints: reward.costPoints,
        status: RedemptionStatus.beklemede,
        createdAt: DateTime.now(),
      ).toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  // ---------------------------------------------------------------
  // OPERATOR ISLEMLERI (yalnizca admins/{uid} olan kullanicilar)
  // ---------------------------------------------------------------

  /// ONAY BEKLEYEN tum odul talepleri (en eski once — sirayla islensin).
  ///
  /// Yetkisi olmayan biri bu akisi dinlerse Firestore permission-denied
  /// dondurur; yani liste arayuzde gizlenmiyor, sunucuda kapali.
  Stream<List<Redemption>> watchPendingRedemptions() {
    return _redemptions
        .where('status', isEqualTo: RedemptionStatus.beklemede.name)
        .snapshots()
        .map((snap) {
      // Siralama istemcide: status filtresi + createdAt siralamasi
      // bilesik indeks gerektirirdi (bkz. ayni gerekce waste_requests'te).
      final list = snap.docs.map(Redemption.fromDoc).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    });
  }

  /// Bir kullanicinin odul taleplerini operator icin okur.
  /// (Bakiye hesabinda kullanilir — kullanicinin gordugu ile ayni veri.)
  Stream<List<Redemption>> watchRedemptionsOf(String userId) =>
      watchUserRedemptions(userId);

  /// Talebi ONAYLAR veya REDDEDER.
  ///
  /// Kural yalnizca [status], [decidedAt] ve [decidedBy] alanlarinin
  /// degismesine izin verir: operator puani, kullaniciyi veya odulun
  /// fiyatini degistiremez. Ayrica sadece 'beklemede' durumundaki bir kayit
  /// karara baglanabilir — verilmis bir karar sonradan cevrilemez.
  Future<void> decideRedemption({
    required String redemptionId,
    required bool approve,
    required String operatorId,
  }) {
    return _redemptions.doc(redemptionId).update({
      'status': approve
          ? RedemptionStatus.onaylandi.name
          : RedemptionStatus.reddedildi.name,
      'decidedAt': FieldValue.serverTimestamp(),
      'decidedBy': operatorId,
    });
  }
}
