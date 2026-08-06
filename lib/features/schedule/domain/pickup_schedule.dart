import 'package:cloud_firestore/cloud_firestore.dart';

import '../../waste_request/domain/models/waste_request_model.dart';

/// Bir isletmenin DUZENLI toplama plani.
///
/// B2B degeri: site yonetimleri ve marketler atigi rastgele degil, belirli
/// bir ritimle biriktirir ("her ayin 3'u"). Plan tanimlandiginda talep
/// olusturmak tek dokunusa iner ve sefer planlamasi ongorulebilir olur.
class PickupSchedule {
  const PickupSchedule({
    required this.id,
    required this.userId,
    required this.label,
    required this.dayOfMonth,
    required this.wasteTypes,
    required this.estimatedKg,
    required this.createdAt,
    this.isActive = true,
  });

  final String id;
  final String userId;

  /// Kullanicinin verdigi ad — "Aylık kâğıt toplama" gibi
  final String label;

  /// Ayin kacinci gunu (1-28).
  ///
  /// UST SINIR 28 BILINCLI: 29/30/31 secilirse subatta (ve 30 cekenlerde)
  /// "olmayan gun" problemi cikar ve bir sonraki tarih kayar. Sinirlamayi
  /// calisma aninda tarih duzeltmesiyle degil, TASARIMDA cozuyoruz.
  final int dayOfMonth;

  final List<WasteType> wasteTypes;
  final double estimatedKg;

  /// Pasife alinan plan. SILME YOK — projenin "veri yok edilmez" ilkesi.
  final bool isActive;

  final DateTime createdAt;

  static const int maxDayOfMonth = 28;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'label': label,
        'dayOfMonth': dayOfMonth,
        'wasteTypes': wasteTypes.map((t) => t.name).toList(),
        'estimatedKg': estimatedKg,
        'isActive': isActive,
      };

  factory PickupSchedule.fromJson(String id, Map<String, dynamic> json) {
    return PickupSchedule(
      id: id,
      userId: json['userId'] as String? ?? '',
      label: json['label'] as String? ?? 'Toplama planı',
      // Bozuk veri arayuzu cokertmesin
      dayOfMonth:
          ((json['dayOfMonth'] as num?)?.toInt() ?? 1).clamp(1, maxDayOfMonth),
      wasteTypes: (json['wasteTypes'] as List? ?? [])
          .map((n) => WasteType.fromName(n as String))
          .toList(),
      estimatedKg: (json['estimatedKg'] as num? ?? 0).toDouble(),
      isActive: json['isActive'] as bool? ?? true,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory PickupSchedule.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      PickupSchedule.fromJson(doc.id, doc.data() ?? {});

  PickupSchedule copyWith({bool? isActive}) => PickupSchedule(
        id: id,
        userId: userId,
        label: label,
        dayOfMonth: dayOfMonth,
        wasteTypes: wasteTypes,
        estimatedKg: estimatedKg,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );

  // ---------------------------------------------------------------
  // TARIH HESABI — saklanmaz, her seferinde turetilir
  // ---------------------------------------------------------------

  /// [from] tarihinden sonraki (veya o gunku) ilk toplama gunu.
  ///
  /// Saat bileseni sifirlanir: "kac gun kaldi" hesabi saatten etkilenmesin.
  DateTime nextOccurrence([DateTime? from]) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (dayOfMonth >= today.day) {
      return DateTime(today.year, today.month, dayOfMonth);
    }
    // Bu ayin gunu gecti -> gelecek ay. DateTime ay tasmasini kendi cozer
    // (ornegin 12. ay + 1 -> gelecek yilin 1. ayi).
    return DateTime(today.year, today.month + 1, dayOfMonth);
  }

  /// Toplama gunune kalan gun sayisi (0 = bugun).
  int daysUntil([DateTime? from]) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return nextOccurrence(now).difference(today).inDays;
  }

  /// Ana Sayfa seridinde gosterilecek metin
  String reminderText([DateTime? from]) {
    final days = daysUntil(from);
    if (days == 0) return 'Planlı toplama gününüz BUGÜN';
    if (days == 1) return 'Planlı toplama gününüz yarın';
    return 'Planlı toplama gününüze $days gün kaldı';
  }

  /// Serit gosterilsin mi? Sadece gun yaklastiginda rahatsiz ediyoruz.
  bool isDueSoon([DateTime? from]) => daysUntil(from) <= reminderWindowDays;

  static const int reminderWindowDays = 3;

  /// Ozet satiri: "Kâğıt, Plastik · ~120 kg · her ayın 3'ü"
  String get summary {
    final types = wasteTypes.map((t) => t.label).join(', ');
    return '$types · ~${estimatedKg.toStringAsFixed(0)} kg · '
        'her ayın $dayOfMonth\'i';
  }

  // ---------------------------------------------------------------
  // TAKVIME AKTARMA
  // ---------------------------------------------------------------

  /// Google Takvim'e TEKRARLAYAN etkinlik ekleme baglantisi.
  ///
  /// NEDEN BOYLE: Uygulama kapaliyken bildirim gondermek FCM + zamanlanmis
  /// Cloud Function ister; o da Blaze plani ister. Bunun yerine hatirlatmayi
  /// isletmenin KENDI takvim sistemine yaziyoruz — telefon kapaliyken bile
  /// calisir ve sifir backend gerektirir. Bu bir kacamak degil, uretimde de
  /// tercih edilen bir yontemdir. (Kendi bildirim kanalimiz Faz 2.)
  String googleCalendarUrl() {
    final next = nextOccurrence();
    // Sabah 09:00 - 10:00 arasi bir etkinlik
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${next.year}${two(next.month)}${two(next.day)}';
    final start = '${day}T090000';
    final end = '${day}T100000';

    final params = {
      'action': 'TEMPLATE',
      'text': 'ATOS · $label',
      'dates': '$start/$end',
      'details': 'ATOS atık toplama planı: $summary\n'
          'Talebinizi uygulamadan tek dokunuşla oluşturabilirsiniz.',
      'recur': 'RRULE:FREQ=MONTHLY;BYMONTHDAY=$dayOfMonth',
    };

    final query = params.entries
        .map((e) =>
            '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    return 'https://calendar.google.com/calendar/render?$query';
  }
}
