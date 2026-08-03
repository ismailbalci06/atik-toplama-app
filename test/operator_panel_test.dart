// OPERATOR PANELI — onay kuyrugunun davranis testleri.
//
// Kritik nokta: operatorun gordugu bakiye ile kullanicinin kendi ekraninda
// gordugu bakiye AYNI hesaptan gelmeli. Iki ayri formul olsaydi operator
// "yetiyor" deyip onaylarken kullanici baska bir sayi goruyor olurdu.
import 'package:atik_toplama_app/features/rewards/domain/green_points.dart';
import 'package:atik_toplama_app/features/rewards/domain/reward_models.dart';
import 'package:atik_toplama_app/features/waste_request/domain/models/waste_request_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

WasteRequest _delivered(double confirmedKg, List<WasteType> types) =>
    WasteRequest(
      id: 'r',
      userId: 'u1',
      wasteTypes: types,
      estimatedKg: confirmedKg,
      confirmedKg: confirmedKg,
      approxLocation: const LatLng(39.6, 32.1),
      createdAt: DateTime.now(),
      status: RequestStatus.tamamlandi,
    );

Redemption _redemption(RedemptionStatus status, int cost) => Redemption(
      id: 'x',
      userId: 'u1',
      rewardId: 'rw',
      rewardTitle: 'Ödül',
      costPoints: cost,
      status: status,
      createdAt: DateTime.now(),
    );

void main() {
  group('Operator ve kullanici AYNI bakiyeyi gorur', () {
    test('PointsWallet.compute tek kaynak', () {
      // 50 kg kagit = 50 * 0.9 * 10 = 450 puan (canli testte dogrulandi)
      final requests = [_delivered(50, const [WasteType.kagit])];
      final redemptions = [_redemption(RedemptionStatus.beklemede, 100)];

      final wallet = PointsWallet.compute(
        requests: requests,
        redemptions: redemptions,
      );

      expect(wallet.earned, 450);
      expect(wallet.spent, 100);
      expect(wallet.balance, 350);
    });

    test('bekleyen talep bakiyeden dusulur (cift harcama olmaz)', () {
      final requests = [_delivered(50, const [WasteType.kagit])]; // 450
      final wallet = PointsWallet.compute(
        requests: requests,
        redemptions: [
          _redemption(RedemptionStatus.beklemede, 200),
          _redemption(RedemptionStatus.beklemede, 200),
        ],
      );
      // Ayni puani iki odule birden harcayamaz
      expect(wallet.balance, 50);
    });

    test('REDDEDILEN talep puani geri birakir', () {
      final requests = [_delivered(50, const [WasteType.kagit])]; // 450
      final wallet = PointsWallet.compute(
        requests: requests,
        redemptions: [
          _redemption(RedemptionStatus.reddedildi, 400),
        ],
      );
      expect(wallet.spent, 0);
      expect(wallet.balance, 450);
    });

    test('ONAYLANAN talep bakiyeden dusuk kalir', () {
      final requests = [_delivered(50, const [WasteType.kagit])]; // 450
      final wallet = PointsWallet.compute(
        requests: requests,
        redemptions: [_redemption(RedemptionStatus.onaylandi, 400)],
      );
      expect(wallet.balance, 50);
    });

    test('bakiyeyi asan talep NEGATIF bakiye gosterir (operator uyarilir)', () {
      final requests = [_delivered(10, const [WasteType.cam])]; // 10*0.3*10=30
      final wallet = PointsWallet.compute(
        requests: requests,
        redemptions: [_redemption(RedemptionStatus.beklemede, 500)],
      );
      expect(wallet.balance, lessThan(0));
    });
  });

  group('Redemption modeli', () {
    test('operator panelinde ad gorunur, yoksa kisa UID', () {
      final withName = Redemption(
        id: 'x',
        userId: 'abcdef123456',
        userName: 'Yeşil Site Yönetimi',
        rewardId: 'rw',
        rewardTitle: 'Ödül',
        costPoints: 100,
        status: RedemptionStatus.beklemede,
        createdAt: DateTime.now(),
      );
      expect(withName.displayName, 'Yeşil Site Yönetimi');

      final withoutName = _redemption(RedemptionStatus.beklemede, 100);
      // Ham UID tamamen basilmaz
      expect(withoutName.displayName.length, lessThanOrEqualTo(7));
    });

    test('toJson karar alanlarini TASIMAZ (onlari operator yazar)', () {
      final json = _redemption(RedemptionStatus.beklemede, 100).toJson();
      expect(json.containsKey('decidedAt'), isFalse);
      expect(json.containsKey('decidedBy'), isFalse);
      // Olusturulan kayit her zaman 'beklemede' baslar
      expect(json['status'], 'beklemede');
    });

    test('fromDoc karar alanlarini geri okur', () {
      final r = Redemption.fromDoc(_FakeDoc({
        'userId': 'u1',
        'userName': 'Test Tesis',
        'rewardId': 'rw',
        'rewardTitle': 'Sertifika',
        'costPoints': 5000,
        'status': 'onaylandi',
        'decidedBy': 'op1',
      }));
      expect(r.status, RedemptionStatus.onaylandi);
      expect(r.decidedBy, 'op1');
      expect(r.costPoints, 5000);
    });
  });
}

/// Firestore dokumani yerine gecen minimal sahte nesne
class _FakeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this._data);
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  String get id => 'fake-id';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
