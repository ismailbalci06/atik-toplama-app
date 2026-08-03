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

  CollectionReference<Map<String, dynamic>> get _rewards =>
      _firestore.collection(_rewardsCollection);

  CollectionReference<Map<String, dynamic>> get _redemptions =>
      _firestore.collection(_redemptionsCollection);

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
    required Reward reward,
  }) async {
    final doc = await _redemptions.add({
      ...Redemption(
        id: '',
        userId: userId,
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
}
