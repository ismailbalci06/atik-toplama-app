import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Atik turlerini temsil eden enum.
/// Yeni bir atik turu eklemek istersek sadece buraya ekleriz;
/// UI (chip listesi) bu enum uzerinden otomatik olusur.
enum WasteType {
  plastik('Plastik', '♳'),
  cam('Cam', '🍾'),
  kagit('Kâğıt', '📄'),
  metal('Metal', '🥫'),
  pil('Pil', '🔋'),
  elektronik('Elektronik', '📱');

  const WasteType(this.label, this.emoji);

  /// Kullaniciya gosterilecek Turkce etiket
  final String label;

  /// Chip uzerinde gosterilecek ikon/emoji
  final String emoji;

  /// Firestore'dan gelen string'i guvenli sekilde enum'a cevirir.
  /// Tanimsiz bir deger gelirse uygulamayi cokertmek yerine plastige duser.
  static WasteType fromName(String name) =>
      WasteType.values.asNameMap()[name] ?? WasteType.plastik;
}

/// Talebin yasam dongusundeki durumlari.
/// Durum akisi: bekliyor -> atandi -> yolda -> tamamlandi (veya iptal).
enum RequestStatus {
  bekliyor,   // Talep olusturuldu, toplayici atanmadi
  atandi,     // Bir toplayici "Talebi Al" dedi
  yolda,      // Toplayici adrese dogru hareket halinde
  tamamlandi, // Atik teslim alindi
  iptal;      // Kullanici veya sistem iptal etti

  /// Firestore'dan gelen string'i guvenli sekilde enum'a cevirir.
  static RequestStatus fromName(String? name) =>
      RequestStatus.values.asNameMap()[name ?? ''] ?? RequestStatus.bekliyor;

  /// Talep hala AKTIF mi? (kullanici tarafinda canli takip edilebilir)
  ///
  /// Tek yerde tanimli olmasi onemli: Ana Sayfa sayaci, gecmis listesindeki
  /// tiklanabilirlik ve haritadaki pin'ler ayni tanimi kullanir; biri
  /// degisirse hepsi birlikte degisir.
  bool get isActive =>
      this == RequestStatus.bekliyor ||
      this == RequestStatus.atandi ||
      this == RequestStatus.yolda;

  /// Talep henuz bir toplayici tarafindan alinmadi mi?
  /// Iptal YALNIZCA bu durumda mumkundur — arac yola ciktiktan sonra
  /// iptal, toplayicinin bosuna yol gitmesi demektir.
  bool get isCancellable => this == RequestStatus.bekliyor;
}

/// GIZLILIK MASKELEMESI — konum hassasiyeti icin izgara yuvarlamasi.
///
/// Neden izgara (grid), rastgele kaydirma degil: rastgele kaydirmada ayni
/// talep her okundugunda farkli bir nokta uretilirse, tekrar tekrar okuyup
/// ortalamasini alan biri gercek konumu geri hesaplayabilir. Izgara
/// yuvarlamasi DETERMINISTIKTIR — ayni talep her zaman ayni hucreye duser,
/// hucre icindeki gercek nokta hicbir sekilde daraltilamaz.
///
/// 0.005 derece ~ 555 m (enlem). Gercek nokta, hucre merkezinin en fazla
/// yarim hucre uzagindadir; haritada 500 m yaricapli cember bunu kapsar.
const double kLocationGridStep = 0.005;

/// Toplama noktasinin HERKESE ACIK, yaklasik gosterimi.
LatLng snapToPrivacyGrid(LatLng exact) {
  double snap(double v) => (v / kLocationGridStep).roundToDouble() *
      kLocationGridStep;
  return LatLng(snap(exact.latitude), snap(exact.longitude));
}

/// Bir talebin HASSAS detaylari — ayri, korumali dokumanda durur.
///
/// GUVENLIK: Firestore kurallari ALAN bazinda filtreleme yapamaz, yalnizca
/// DOKUMAN bazinda. Bu yuzden acik adres (tam koordinat) ve kullanici notu
/// ana dokumanda DURAMAZ; `waste_requests/{id}/private/detail` alt
/// dokumaninda durur ve kural sadece talebin sahibine + ATANMIS toplayiciya
/// okuma izni verir. Maske boylece istemcide degil SUNUCUDA kalkar.
class RequestDetail {
  const RequestDetail({
    required this.ownerId,
    required this.exactLocation,
    this.note,
  });

  /// Talep sahibinin UID'si — kural bunu okuma izni icin kullanir
  final String ownerId;

  /// Toplama noktasinin TAM koordinati
  final LatLng exactLocation;

  /// Kullanicinin acik adres/kat/kapici gibi detay notu
  final String? note;

  Map<String, dynamic> toJson() => {
        'ownerId': ownerId,
        'exactLocation':
            GeoPoint(exactLocation.latitude, exactLocation.longitude),
        'note': note,
      };

  factory RequestDetail.fromJson(Map<String, dynamic> json) {
    final geo = json['exactLocation'] as GeoPoint? ?? const GeoPoint(0, 0);
    return RequestDetail(
      ownerId: json['ownerId'] as String? ?? '',
      exactLocation: LatLng(geo.latitude, geo.longitude),
      note: json['note'] as String?,
    );
  }
}

/// Yeni talep olusturulurken formdan gelen ham girdi.
///
/// Ayri bir tip olmasi bilincli: form TAM konumu ve notu tasir, ama bunlarin
/// hangisinin acik hangisinin korumali dokumana yazilacagina REPOSITORY
/// karar verir. Boylece "yanlislikla hassas alani ana dokumana yazma"
/// hatasi tek bir yerde onlenir.
class NewRequestInput {
  const NewRequestInput({
    required this.wasteTypes,
    required this.estimatedKg,
    required this.exactLocation,
    this.note,
  });

  final List<WasteType> wasteTypes;
  final double estimatedKg;
  final LatLng exactLocation;
  final String? note;
}

/// Bir atik toplama talebini temsil eden model sinifi (ACIK dokuman).
///
/// Bu sinifta HASSAS VERI YOKTUR: tam koordinat ve kullanici notu
/// [RequestDetail] icinde, korumali alt dokumanda durur.
///
/// Firestore uyumu:
/// - Konum, Firestore'un yerel [GeoPoint] tipiyle saklanir (cografi sorgu
///   yapilabilir olmasi icin).
/// - Zaman alanlari [Timestamp] olarak saklanir; olusturmada sunucu saati
///   (FieldValue.serverTimestamp) kullanilir ki cihaz saatleri arasindaki
///   farklar siralamayi bozmasin.
class WasteRequest {
  final String id;                  // Benzersiz talep ID'si (dokuman ID)
  final String userId;              // Talebi olusturan kullanicinin ID'si
  final List<WasteType> wasteTypes; // Secilen atik turleri (coklu secim)
  final double estimatedKg;         // Tahmini agirlik (kg) — KULLANICI BEYANI

  /// Toplayicinin teslim alirken ONAYLADIGI gercek miktar (kg).
  ///
  /// NEDEN VAR: [estimatedKg] kullanicinin kendi beyanidir. Yesil Puan
  /// ekonomisi beyan uzerine kurulsaydi, kullanici miktari sisirip puan
  /// uretebilirdi. Bu yuzden PUAN YALNIZCA bu alandan hesaplanir; alan
  /// sadece teslimati yapan toplayici tarafindan doldurulur.
  ///
  /// Teslimat tamamlanana kadar null'dir.
  final double? confirmedKg;

  /// Puana ve etkiye esas alinacak miktar.
  /// Onaylanmis kilo varsa o, yoksa beyan (yalnizca ETKI tahmininde
  /// kullanilir — puan hesabi onaysiz teslimati hic saymaz).
  double get effectiveKg => confirmedKg ?? estimatedKg;

  /// YAKLASIK toplama konumu (~500 m izgaraya yuvarlanmis).
  /// Herkese aciktir; tam koordinat icin [RequestDetail] gerekir.
  final LatLng approxLocation;

  final RequestStatus status;       // Talebin guncel durumu
  final DateTime createdAt;         // Olusturulma zamani (sunucu saati)
  final String? collectorId;        // Talebi alan toplayicinin ID'si
  final DateTime? acceptedAt;       // Talebin alinma zamani

  /// CANLI toplayici konumu — TEK GERCEK KAYNAK (single source of truth).
  /// Toplayici cihazi yolculuk boyunca bu alani gunceller; kullanicinin
  /// takip ekrani da SADECE bunu dinler. Boylece iki ekran ayni gercegi
  /// gosterir (daha once her ekran kendi simulasyonunu cizdigi icin
  /// baslangic noktalari birbirini tutmuyordu).
  final LatLng? collectorLocation;

  /// Aracin yonu (derece) — isaretcinin dogru yone bakmasi icin
  final double? collectorBearing;

  /// Talebi alan toplayicinin ADI — kullanicinin takip ekraninda gosterilir.
  /// (Onceden sabit "Ahmet Yılmaz" yaziyordu; artik gercek hesaptan gelir.)
  final String? collectorName;

  const WasteRequest({
    required this.id,
    required this.userId,
    required this.wasteTypes,
    required this.estimatedKg,
    required this.approxLocation,
    required this.createdAt,
    this.confirmedKg,
    this.status = RequestStatus.bekliyor,
    this.collectorId,
    this.acceptedAt,
    this.collectorLocation,
    this.collectorBearing,
    this.collectorName,
  });

  /// Modeli Firestore'a yazilacak JSON'a cevirir.
  ///
  /// NOT: createdAt bilerek DAHIL EDILMEZ — olusturma aninda repository
  /// FieldValue.serverTimestamp() ekler. Boylece zaman damgasi her zaman
  /// sunucudan gelir, cihaz saatine guvenilmez.
  /// GUVENLIK: Burada 'note' ve tam koordinat YOKTUR ve OLMAMALIDIR.
  /// Firestore kurali da bu iki anahtari ana dokumanda reddeder — yani
  /// ileride biri yanlislikla eklerse yazma sunucuda basarisiz olur.
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'wasteTypes': wasteTypes.map((t) => t.name).toList(),
      'estimatedKg': estimatedKg,
      'confirmedKg': confirmedKg,
      'approxLocation':
          GeoPoint(approxLocation.latitude, approxLocation.longitude),
      'status': status.name,
      'collectorId': collectorId,
      'acceptedAt':
          acceptedAt == null ? null : Timestamp.fromDate(acceptedAt!),
      'collectorLocation': collectorLocation == null
          ? null
          : GeoPoint(collectorLocation!.latitude, collectorLocation!.longitude),
      'collectorBearing': collectorBearing,
      'collectorName': collectorName,
    };
  }

  /// Firestore dokumanini model nesnesine cevirir.
  ///
  /// [id] dokuman ID'sinden gelir (dokumanin icinde ayrica saklanmaz —
  /// tek dogruluk kaynagi Firestore'un kendi ID'sidir).
  /// serverTimestamp henuz sunucuya islenmemisken null gelebilir;
  /// bu durumda gecici olarak cihaz saati kullanilir.
  factory WasteRequest.fromJson(String id, Map<String, dynamic> json) {
    // Yeni sema: approxLocation. ESKI dokumanlar (gizlilik yamasindan once
    // olusturulmus) tam koordinati 'location' alaninda tasiyor — onlari da
    // izgaraya yuvarlayarak okuyoruz ki arayuz eski veride de maskeli
    // kalsin. (Eski dokumanlarin Firestore'daki hali yine de hassastir;
    // kalici cozum Console'dan temizlemektir.)
    final geo = json['approxLocation'] as GeoPoint? ??
        json['location'] as GeoPoint? ??
        const GeoPoint(0, 0);
    final raw = LatLng(geo.latitude, geo.longitude);
    final approx = json['approxLocation'] == null
        ? snapToPrivacyGrid(raw) // eski kayit: yuvarlayarak goster
        : raw;

    return WasteRequest(
      id: id,
      userId: json['userId'] as String? ?? '',
      wasteTypes: (json['wasteTypes'] as List? ?? [])
          .map((name) => WasteType.fromName(name as String))
          .toList(),
      estimatedKg: (json['estimatedKg'] as num? ?? 0).toDouble(),
      confirmedKg: (json['confirmedKg'] as num?)?.toDouble(),
      approxLocation: approx,
      status: RequestStatus.fromName(json['status'] as String?),
      createdAt:
          (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      collectorId: json['collectorId'] as String?,
      acceptedAt: (json['acceptedAt'] as Timestamp?)?.toDate(),
      // CANLI toplayici konumu (henuz atanmadiysa null)
      collectorLocation: json['collectorLocation'] == null
          ? null
          : LatLng(
              (json['collectorLocation'] as GeoPoint).latitude,
              (json['collectorLocation'] as GeoPoint).longitude,
            ),
      collectorBearing: (json['collectorBearing'] as num?)?.toDouble(),
      collectorName: json['collectorName'] as String?,
    );
  }

  /// Firestore snapshot'indan dogrudan model uretir (stream'lerde kullanilir).
  factory WasteRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      WasteRequest.fromJson(doc.id, doc.data() ?? {});

  /// Immutable model uzerinde alan degistirerek kopya uretir.
  WasteRequest copyWith({
    RequestStatus? status,
    String? collectorId,
    DateTime? acceptedAt,
  }) {
    return WasteRequest(
      id: id,
      userId: userId,
      wasteTypes: wasteTypes,
      estimatedKg: estimatedKg,
      confirmedKg: confirmedKg,
      approxLocation: approxLocation,
      createdAt: createdAt,
      status: status ?? this.status,
      collectorId: collectorId ?? this.collectorId,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }
}
