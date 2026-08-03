import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../domain/models/waste_request_model.dart';

/// Atik talepleri icin Firestore erisim katmani.
///
/// TUM Firestore islemleri bu siniftan gecer — UI ve provider'lar
/// asla dogrudan FirebaseFirestore'a dokunmaz. Boylece:
/// - Koleksiyon/alan adlari tek yerde durur,
/// - Test yazarken bu sinif kolayca mock'lanir,
/// - Ileride backend degisse bile sadece bu dosya guncellenir.
class WasteRequestRepository {
  WasteRequestRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Koleksiyon adi tek yerden yonetilir
  static const _collectionName = 'waste_requests';

  /// Tip guvenli koleksiyon referansi
  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection(_collectionName);

  /// HASSAS detay dokumaninin yolu: waste_requests/{id}/private/detail
  ///
  /// Alt koleksiyon olmasi bilincli: Firestore kurallari alan bazinda
  /// filtreleyemez, doküman bazinda filtreler. Tam koordinat ve not ayri
  /// dokumanda oldugu icin kural onlari talep sahibi + atanmis toplayici
  /// disinda HERKESE kapatabiliyor.
  static const _privateSub = 'private';
  static const _detailDoc = 'detail';

  DocumentReference<Map<String, dynamic>> _detailRef(String requestId) =>
      _requests.doc(requestId).collection(_privateSub).doc(_detailDoc);

  // ---------------------------------------------------------------
  // YAZMA ISLEMLERI
  // ---------------------------------------------------------------

  /// Yeni talep olusturur ve olusan dokuman ID'sini dondurur.
  ///
  /// GIZLILIK MIMARISI — talep IKI dokumana yazilir:
  ///   1. waste_requests/{id}          -> yaklasik konum, tur, kg (acik)
  ///   2. waste_requests/{id}/private/detail -> TAM konum + not (korumali)
  ///
  /// Ikisi tek bir WriteBatch ile atomik yazilir: ya ikisi de olusur ya
  /// hicbiri. Aksi halde "acik dokuman var ama adresi yok" gibi yarim bir
  /// talep olusabilir ve toplayici adrese hic ulasamazdi.
  ///
  /// Yaklasik konumu BURADA hesapliyoruz (cagiran ekranda degil): boylece
  /// tam koordinatin ana dokumana sizmasi yapisal olarak imkansiz.
  ///
  /// createdAt alanini SUNUCU saati ile ekler (serverTimestamp) —
  /// boylece siralama, cihaz saatleri yanlis olsa bile dogru kalir.
  Future<String> addRequest({
    required NewRequestInput input,
    required String userId,
  }) async {
    final docRef = _requests.doc(); // ID'yi onceden al (batch icin gerekli)

    final publicData = WasteRequest(
      id: docRef.id,
      userId: userId,
      wasteTypes: input.wasteTypes,
      estimatedKg: input.estimatedKg,
      approxLocation: snapToPrivacyGrid(input.exactLocation),
      createdAt: DateTime.now(), // toJson'a girmez; sunucu saati kullanilir
    ).toJson();

    final detail = RequestDetail(
      ownerId: userId,
      exactLocation: input.exactLocation,
      note: input.note,
    );

    final batch = _firestore.batch();
    batch.set(docRef, {
      ...publicData,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_detailRef(docRef.id), detail.toJson());
    await batch.commit();

    return docRef.id;
  }

  /// Talebin HASSAS detayini (tam konum + not) tek seferlik okur.
  ///
  /// Yetkisi olmayan biri cagirirsa Firestore permission-denied firlatir —
  /// yani maske arayuzde degil SUNUCUDA uygulanir. Yetki: talep sahibi
  /// veya talebi uzerine almis toplayici.
  Future<RequestDetail?> getDetail(String requestId) async {
    final doc = await _detailRef(requestId).get();
    if (!doc.exists) return null;
    return RequestDetail.fromJson(doc.data() ?? {});
  }

  /// Talebin hassas detayinin canli akisi (takip ekrani icin).
  Stream<RequestDetail?> watchDetail(String requestId) {
    return _detailRef(requestId).snapshots().map(
          (doc) => doc.exists ? RequestDetail.fromJson(doc.data() ?? {}) : null,
        );
  }

  /// Toplayicinin talebi uzerine almasi.
  ///
  /// Transaction kullanilir: iki toplayici ayni anda "Talebi Al" derse
  /// yalnizca ILKI kazanir, ikincisi hata alir (yarim kalmis/cakisan
  /// atama olusamaz). Bu, gercek zamanli sistemlerde kritik bir korumadir.
  /// [collectorLocation] talebin alindigi ANDAKI toplayici konumudur.
  /// Kullanicinin takip ekrani rotayi tam bu noktadan cizer — boylece iki
  /// ekran ayni baslangic noktasini kullanir (tek gercek kaynak).
  Future<void> acceptRequest({
    required String requestId,
    required String collectorId,
    required String collectorName,
    required LatLng collectorLocation,
  }) {
    return _firestore.runTransaction((transaction) async {
      final docRef = _requests.doc(requestId);
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        throw StateError('Talep bulunamadı (silinmiş olabilir).');
      }

      final currentStatus =
          RequestStatus.fromName(snapshot.data()?['status'] as String?);
      if (currentStatus != RequestStatus.bekliyor) {
        throw StateError('Bu talep başka bir toplayıcı tarafından alındı.');
      }

      transaction.update(docRef, {
        'status': RequestStatus.atandi.name,
        'collectorId': collectorId,
        'collectorName': collectorName,
        'acceptedAt': FieldValue.serverTimestamp(),
        // Rota baslangici: iki ekran da bu noktayi kullanir
        'collectorLocation': GeoPoint(
          collectorLocation.latitude,
          collectorLocation.longitude,
        ),
      });
    });
  }

  /// Toplayicinin CANLI konumunu talebe yazar (yolculuk boyunca periyodik).
  ///
  /// Kullanicinin takip ekrani bu alani dinledigi icin, arac gercekten
  /// toplayici cihazindan gelen konumla hareket eder — iki ekran arasindaki
  /// "veri kopmasi" (desync) bu sayede ortadan kalkar.
  /// NOT: Cagri sikligi cagiran tarafta kisitlanir (yazma maliyeti icin).
  Future<void> updateCollectorLocation({
    required String requestId,
    required LatLng position,
    required double bearing,
  }) {
    return _requests.doc(requestId).update({
      'collectorLocation': GeoPoint(position.latitude, position.longitude),
      'collectorBearing': bearing,
      'status': RequestStatus.yolda.name,
    });
  }

  /// Talebin durumunu gunceller (yolda / tamamlandi / iptal gecisleri).
  Future<void> updateStatus({
    required String requestId,
    required RequestStatus status,
  }) {
    return _requests.doc(requestId).update({'status': status.name});
  }

  /// Teslimati TAMAMLAR ve toplayicinin onayladigi gercek miktari yazar.
  ///
  /// Durum ve onayli miktar TEK yazmada gider: "tamamlandi ama miktari yok"
  /// gibi bir ara durum olusamaz. Yesil Puan yalnizca [confirmedKg] uzerinden
  /// hesaplandigi icin bu alanin eksik kalmasi puan kaybi demek olurdu.
  Future<void> completeRequest({
    required String requestId,
    required double confirmedKg,
  }) {
    return _requests.doc(requestId).update({
      'status': RequestStatus.tamamlandi.name,
      'confirmedKg': confirmedKg,
    });
  }

  // ---------------------------------------------------------------
  // CANLI OKUMA (STREAM) ISLEMLERI
  // ---------------------------------------------------------------

  /// Toplayici ekrani icin: BEKLEYEN taleplerin canli akisi.
  ///
  /// Firestore'da yeni talep olustugu/degistigi ANDA bu stream yeni
  /// listeyi yayinlar — toplayicinin haritasindaki pinler kendiliginden
  /// guncellenir, yenileme butonuna gerek kalmaz.
  Stream<List<WasteRequest>> getPendingRequests() {
    return _requests
        .where('status', isEqualTo: RequestStatus.bekliyor.name)
        .snapshots()
        // NOT: Siralama (orderBy) sunucuda DEGIL, istemcide yapiliyor.
        // 'status' esitlik filtresi + 'createdAt' siralamasi Firestore'da
        // bileSik indeks (composite index) gerektirir; indeks yoksa sorgu
        // hata verir. Bekleyen talep sayisi kucuk oldugu icin istemci
        // tarafinda siralamak hem indeks bagimliligini kaldirir hem yeterli.
        // (Uretimde: Console'dan status+createdAt bileSik indeksi olusturup
        //  tekrar sunucu siralamasina donulebilir.)
        .map((snapshot) => _sortedByNewest(snapshot));
  }

  /// Snapshot dokumanlarini modele cevirip olusturma zamanina gore
  /// (en yeni once) siralar.
  List<WasteRequest> _sortedByNewest(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final list = snapshot.docs.map(WasteRequest.fromDoc).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Tek bir talebin canli akisi.
  ///
  /// Kullanicinin "talebim ne durumda?" ekrani bunu dinler:
  /// toplayici "Talebi Al" dediginde status 'atandi' olur ve kullanici
  /// tarafi otomatik olarak "Talebim Yolda" ekranina gecer (Asama 2).
  Stream<WasteRequest?> watchRequest(String requestId) {
    return _requests.doc(requestId).snapshots().map(
          (doc) => doc.exists ? WasteRequest.fromDoc(doc) : null,
        );
  }

  /// Etki panosu icin: TAMAMLANMIS taleplerin canli akisi.
  /// Tek alan esitlik filtresi oldugu icin bileSik indeks gerektirmez.
  /// (Olcekte: her okuma tum tamamlanmis dokumanlari cektiginden, uretimde
  ///  Cloud Function ile guncellenen bir sayac/aggregate dokumana tasinir.)
  Stream<List<WasteRequest>> getCompletedRequests() {
    return _requests
        .where('status', isEqualTo: RequestStatus.tamamlandi.name)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(WasteRequest.fromDoc).toList());
  }

  /// Bir kullanicinin kendi taleplerinin canli akisi (gecmis/aktif liste).
  Stream<List<WasteRequest>> getRequestsByUser(String userId) {
    return _requests
        .where('userId', isEqualTo: userId)
        .snapshots()
        // Ayni sebeple siralama istemcide (bkz. getPendingRequests notu)
        .map((snapshot) => _sortedByNewest(snapshot));
  }
}
