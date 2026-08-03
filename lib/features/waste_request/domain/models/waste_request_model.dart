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

/// Bir atik toplama talebini temsil eden model sinifi.
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
  final double estimatedKg;         // Tahmini agirlik (kg)
  final String? note;               // Kullanicinin opsiyonel notu
  final LatLng location;            // Toplama noktasinin koordinati
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
    required this.location,
    required this.createdAt,
    this.note,
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
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'wasteTypes': wasteTypes.map((t) => t.name).toList(),
      'estimatedKg': estimatedKg,
      'note': note,
      'location': GeoPoint(location.latitude, location.longitude),
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
    final geo = json['location'] as GeoPoint? ?? const GeoPoint(0, 0);
    return WasteRequest(
      id: id,
      userId: json['userId'] as String? ?? '',
      wasteTypes: (json['wasteTypes'] as List? ?? [])
          .map((name) => WasteType.fromName(name as String))
          .toList(),
      estimatedKg: (json['estimatedKg'] as num? ?? 0).toDouble(),
      note: json['note'] as String?,
      location: LatLng(geo.latitude, geo.longitude),
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
      note: note,
      location: location,
      createdAt: createdAt,
      status: status ?? this.status,
      collectorId: collectorId ?? this.collectorId,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }
}
