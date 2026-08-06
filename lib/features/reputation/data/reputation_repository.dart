import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/collector_reputation.dart';

/// Guvenilirlik puanlari icin Firestore erisim katmani.
///
/// Projenin kurali burada da gecerli: UI ve provider'lar asla dogrudan
/// FirebaseFirestore'a dokunmaz.
///
/// IZOLE EKLENTI: `waste_requests` semasina TEK BIR ALAN bile eklenmedi.
/// Puanlar kendi koleksiyonunda yasar ve cekirdege yalnizca requestId /
/// collectorId ile baglanir. Boylece mevcut akislar ve testler etkilenmez.
class ReputationRepository {
  ReputationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const _collectionName = 'ratings';

  CollectionReference<Map<String, dynamic>> get _ratings =>
      _firestore.collection(_collectionName);

  /// Bir teslimati puanlar.
  ///
  /// Dokuman ID'si TALEP ID'sidir: ayni teslimata ikinci kez puan vermek
  /// yapisal olarak imkansizdir. Yine de `set` yerine bilincli olarak
  /// dogrudan set kullaniyoruz — kural `update` islemini kapattigi icin
  /// var olan bir puanin uzerine yazma sunucuda reddedilir.
  Future<void> rateDelivery(Rating rating) {
    return _ratings.doc(rating.requestId).set({
      ...rating.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Bir teslimatin puani (verilmemisse null).
  /// "Bu teslimati puanladim mi?" sorusunun tek dokumanlik cevabi.
  Stream<Rating?> watchRatingFor(String requestId) {
    if (requestId.isEmpty) return Stream.value(null);
    return _ratings
        .doc(requestId)
        .snapshots()
        .map((doc) => doc.exists ? Rating.fromDoc(doc) : null);
  }

  /// Bir toplayicinin TUM puanlari — karne bundan turetilir.
  ///
  /// Tek alan esitlik filtresi oldugu icin bilesik indeks gerektirmez
  /// (projedeki diger sorgularla ayni gerekce).
  Stream<List<Rating>> watchRatingsOf(String collectorId) {
    if (collectorId.isEmpty) return Stream.value(const []);
    return _ratings
        .where('collectorId', isEqualTo: collectorId)
        .snapshots()
        .map((snap) => snap.docs.map(Rating.fromDoc).toList());
  }
}
