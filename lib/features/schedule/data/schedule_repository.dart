import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/pickup_schedule.dart';

/// Toplama planlari icin Firestore erisim katmani.
///
/// IZOLE EKLENTI: `waste_requests` semasina dokunulmadi. Planlar kendi
/// koleksiyonunda yasar; bir plandan talep olusturuldugunda normal
/// [WasteRequestRepository.addRequest] akisi kullanilir. Yani sevkiyat
/// cekirdegi bu modulden HABERSIZDIR — kirilma yuzeyi yok.
class ScheduleRepository {
  ScheduleRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const _collectionName = 'schedules';

  CollectionReference<Map<String, dynamic>> get _schedules =>
      _firestore.collection(_collectionName);

  /// Kullanicinin planlarinin canli akisi.
  ///
  /// Siralama ISTEMCIDE: 'userId' esitligi + 'createdAt' siralamasi
  /// bilesik indeks gerektirirdi (projedeki diger sorgularla ayni gerekce).
  Stream<List<PickupSchedule>> watchSchedulesOf(String userId) {
    if (userId.isEmpty) return Stream.value(const []);
    return _schedules
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(PickupSchedule.fromDoc).toList()
        ..sort((a, b) => a.dayOfMonth.compareTo(b.dayOfMonth));
      return list;
    });
  }

  Future<String> addSchedule(PickupSchedule schedule) async {
    final doc = await _schedules.add({
      ...schedule.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Plani pasife alir / geri acar.
  ///
  /// SILME YOK: projenin "veri yok edilmez" ilkesi burada da gecerli
  /// (kural: delete kapali). Pasif plan hatirlatma uretmez ama gecmisi
  /// kaybolmaz.
  Future<void> setActive({
    required String scheduleId,
    required bool isActive,
  }) {
    return _schedules.doc(scheduleId).update({'isActive': isActive});
  }
}
