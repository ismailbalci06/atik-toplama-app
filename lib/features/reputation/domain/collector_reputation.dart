import 'package:cloud_firestore/cloud_firestore.dart';

/// Bir teslimat icin verilen GUVENILIRLIK PUANI.
///
/// ANAHTAR TASARIMI: Firestore'daki dokuman ID'si TALEP ID'sidir
/// (`ratings/{requestId}`). Bu tesadufi degil:
///   • Bir teslimata ikinci kez puan vermek YAPISAL olarak imkansiz olur —
///     mukerrer kayit kural yazarak degil, anahtar secerek engellenir.
///   • "Bu talep puanlanmis mi?" sorusu tek bir dokuman okumasidir.
class Rating {
  const Rating({
    required this.requestId,
    required this.collectorId,
    required this.raterId,
    required this.stars,
    required this.createdAt,
    this.comment,
  });

  /// Puanlanan teslimatin ID'si (= dokuman ID'si)
  final String requestId;

  /// Puani ALAN toplayici
  final String collectorId;

  /// Puani VEREN isletme (talebin sahibi)
  final String raterId;

  /// 1-5 arasi yildiz
  final int stars;

  /// Opsiyonel kisa yorum
  final String? comment;

  final DateTime createdAt;

  /// NOT: createdAt burada YOK — repository serverTimestamp ekler.
  /// requestId de yok: o dokuman ID'sinin kendisi.
  Map<String, dynamic> toJson() => {
        'collectorId': collectorId,
        'raterId': raterId,
        'stars': stars,
        if (comment != null && comment!.trim().isNotEmpty)
          'comment': comment!.trim(),
      };

  factory Rating.fromJson(String requestId, Map<String, dynamic> json) {
    return Rating(
      requestId: requestId,
      collectorId: json['collectorId'] as String? ?? '',
      raterId: json['raterId'] as String? ?? '',
      // Bozuk veri arayuzu cokertmesin: gecersiz deger 1-5'e kirpilir
      stars: ((json['stars'] as num?)?.toInt() ?? 0).clamp(1, 5),
      comment: json['comment'] as String?,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Rating.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Rating.fromJson(doc.id, doc.data() ?? {});
}

/// Bir toplayicinin GUVENILIRLIK KARNESI.
///
/// MIMARI: Ortalama puan HICBIR YERDE SAKLANMAZ — tıpkı Yesil Puan
/// bakiyesi gibi, ham kayitlardan her seferinde TURETILIR.
/// Yazilabilir bir "ortalama" alani olmadigi icin sisirilecek bir alan da
/// yoktur; bir toplayici kendi karnesini degistiremez.
///
/// (Olcekte: her okuma toplayicinin tum puanlarini ceker. Uretimde Cloud
///  Functions ile guncellenen bir ozet dokumana tasinir — Faz 2.)
class CollectorReputation {
  const CollectorReputation({
    required this.average,
    required this.count,
    required this.distribution,
  });

  /// Ortalama yildiz (puan yoksa 0)
  final double average;

  /// Toplam puanlanmis teslimat sayisi
  final int count;

  /// Yildiz -> adet dagilimi (1..5)
  final Map<int, int> distribution;

  static const empty = CollectorReputation(
    average: 0,
    count: 0,
    distribution: {},
  );

  static CollectorReputation compute(List<Rating> ratings) {
    if (ratings.isEmpty) return empty;

    final dist = <int, int>{};
    var total = 0;
    for (final r in ratings) {
      total += r.stars;
      dist[r.stars] = (dist[r.stars] ?? 0) + 1;
    }

    return CollectorReputation(
      average: total / ratings.length,
      count: ratings.length,
      distribution: dist,
    );
  }

  /// Henuz hic puan almamis toplayici
  bool get isNew => count == 0;

  /// Ekranda gosterilecek puan metni
  String get displayScore => isNew ? '—' : average.toStringAsFixed(1);

  /// GUVENILIR GOREVLI rozeti.
  ///
  /// Esik bilincli olarak iki kosullu: yuksek ortalama TEK BASINA yeterli
  /// degil, arkasinda yeterli teslimat da olmali. Tek 5 yildizla "guvenilir"
  /// etiketi dagitmak rozeti anlamsizlastirirdi.
  bool get isTrusted => count >= _trustedMinDeliveries && average >= 4.5;

  static const int _trustedMinDeliveries = 5;

  /// Kisa durum etiketi
  String get label {
    if (isNew) return 'Yeni görevli';
    if (isTrusted) return 'Güvenilir görevli';
    return '$count değerlendirme';
  }
}
