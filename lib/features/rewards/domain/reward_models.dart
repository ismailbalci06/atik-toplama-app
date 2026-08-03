import 'package:cloud_firestore/cloud_firestore.dart';

/// Odul katalogundaki tek bir odul.
///
/// Katalog UYGULAMADAN YAZILAMAZ: Firestore kurali `rewards` koleksiyonuna
/// yalnizca okuma izni verir, yazma Console'dan (yonetici) yapilir. Boylece
/// kimse kendine 0 puanlik odul tanimlayamaz.
class Reward {
  const Reward({
    required this.id,
    required this.title,
    required this.costPoints,
    this.description = '',
    this.emoji = '🎁',
    this.isActive = true,
  });

  final String id;
  final String title;
  final String description;

  /// Odulun fiyati (Yesil Puan)
  final int costPoints;

  /// Katalogdaki gorsel ikon
  final String emoji;

  /// Pasif oduller listede gosterilmez (Console'dan kapatilabilir)
  final bool isActive;

  factory Reward.fromJson(String id, Map<String, dynamic> json) => Reward(
        id: id,
        title: json['title'] as String? ?? 'Ödül',
        description: json['description'] as String? ?? '',
        costPoints: (json['costPoints'] as num? ?? 0).toInt(),
        emoji: json['emoji'] as String? ?? '🎁',
        isActive: json['isActive'] as bool? ?? true,
      );

  factory Reward.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Reward.fromJson(doc.id, doc.data() ?? {});
}

/// Odul talebinin durumu.
///
/// Otomatik onay YOK: talep 'beklemede' olarak dusar ve ATOS operatoru
/// Console'dan onaylar. Sebep durustce: Firestore kurallari "bakiyesi
/// yetiyor mu" hesabini yapamaz (toplam gerektirir). Bu yuzden bakiye
/// kontrolu arayuzde YAPILIR ama SON SOZ operatorde olur — kotu niyetli
/// biri bakiyesini asan bir talep olustursa bile eline gecen sey
/// reddedilecek bir kayittir.
enum RedemptionStatus {
  beklemede,
  onaylandi,
  reddedildi;

  static RedemptionStatus fromName(String? name) =>
      RedemptionStatus.values.asNameMap()[name ?? ''] ??
      RedemptionStatus.beklemede;

  /// Bu talep kullanicinin bakiyesinden DUSULUR mu?
  /// Reddedilen talep puani geri birakir.
  bool get holdsPoints => this != RedemptionStatus.reddedildi;

  String get label => switch (this) {
        RedemptionStatus.beklemede => 'Onay bekliyor',
        RedemptionStatus.onaylandi => 'Onaylandı',
        RedemptionStatus.reddedildi => 'Reddedildi',
      };
}

/// Kullanicinin bir odul icin olusturdugu talep.
class Redemption {
  const Redemption({
    required this.id,
    required this.userId,
    required this.rewardId,
    required this.rewardTitle,
    required this.costPoints,
    required this.status,
    required this.createdAt,
    this.userName,
    this.decidedAt,
    this.decidedBy,
  });

  final String id;
  final String userId;

  /// Talebi olusturan tesisin adi — operator panelinde ham UID yerine
  /// okunabilir bir isim gorunsun diye kaydin icine yazilir.
  final String? userName;

  final String rewardId;

  /// Odulun o ANDAKI adi ve fiyati kaydin icine yazilir.
  /// Katalog sonradan degisirse gecmis talep carpilmaz (muhasebe ilkesi).
  final String rewardTitle;
  final int costPoints;

  final RedemptionStatus status;
  final DateTime createdAt;

  /// Kararin verildigi an (operator onayladi/reddetti)
  final DateTime? decidedAt;

  /// Karari veren operatorun UID'si — kim onayladi izi kalir
  final String? decidedBy;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'rewardId': rewardId,
        'rewardTitle': rewardTitle,
        'costPoints': costPoints,
        'status': status.name,
      };

  factory Redemption.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data() ?? {};
    return Redemption(
      id: doc.id,
      userId: json['userId'] as String? ?? '',
      userName: json['userName'] as String?,
      rewardId: json['rewardId'] as String? ?? '',
      rewardTitle: json['rewardTitle'] as String? ?? 'Ödül',
      costPoints: (json['costPoints'] as num? ?? 0).toInt(),
      status: RedemptionStatus.fromName(json['status'] as String?),
      createdAt:
          (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      decidedAt: (json['decidedAt'] as Timestamp?)?.toDate(),
      decidedBy: json['decidedBy'] as String?,
    );
  }

  /// Operator panelinde gosterilecek ad — yoksa kisa UID'ye duser
  String get displayName {
    final n = userName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return userId.length <= 6 ? userId : '${userId.substring(0, 6)}…';
  }
}
