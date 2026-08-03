// YESIL PUAN EKONOMISI — regresyon testleri.
//
// Bu dosyanin en kritik testi "beyan puan uretmez"dir: puan yalnizca
// toplayicinin onayladigi kilodan dogar. Bu kural bozulursa kullanici
// slider'i 250 kg'a cekip puan basabilir; gamification'in tum guvenilirligi
// buna bagli.
import 'package:atik_toplama_app/features/impact/domain/impact_stats.dart';
import 'package:atik_toplama_app/features/rewards/domain/green_points.dart';
import 'package:atik_toplama_app/features/rewards/domain/reward_models.dart';
import 'package:atik_toplama_app/features/waste_request/domain/models/waste_request_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

WasteRequest _req({
  required RequestStatus status,
  double estimatedKg = 100,
  double? confirmedKg,
  List<WasteType> types = const [WasteType.plastik],
}) =>
    WasteRequest(
      id: 'r',
      userId: 'u1',
      wasteTypes: types,
      estimatedKg: estimatedKg,
      confirmedKg: confirmedKg,
      approxLocation: const LatLng(39.6, 32.1),
      createdAt: DateTime.now(),
      status: status,
    );

void main() {
  group('Puan yalnizca ONAYLI kilodan dogar', () {
    test('onay yoksa SIFIR puan (beyan puan uretmez)', () {
      final r = _req(
        status: RequestStatus.tamamlandi,
        estimatedKg: 250, // kullanici sisirmis olabilir
        confirmedKg: null, // ama toplayici onaylamamis
      );
      expect(GreenPoints.forRequest(r), 0);
    });

    test('tamamlanmamis talep puan uretmez', () {
      final r = _req(status: RequestStatus.yolda, confirmedKg: 100);
      expect(GreenPoints.forRequest(r), 0);
    });

    test('iptal edilen talep puan uretmez', () {
      final r = _req(status: RequestStatus.iptal, confirmedKg: 100);
      expect(GreenPoints.forRequest(r), 0);
    });

    test('puan BEYANDAN degil ONAYDAN hesaplanir', () {
      // Beyan 250, onay 50 -> puan 50 kg uzerinden olmali
      final r = _req(
        status: RequestStatus.tamamlandi,
        estimatedKg: 250,
        confirmedKg: 50,
        types: const [WasteType.plastik],
      );
      final expected =
          (50 * ImpactStats.co2PerKg[WasteType.plastik]! * 10).round();
      expect(GreenPoints.forRequest(r), expected);
    });
  });

  group('Puan dagilimi karbon tablosundan gelir', () {
    test('metal, ayni kiloda camdan cok daha fazla puan getirir', () {
      final metal = _req(
        status: RequestStatus.tamamlandi,
        confirmedKg: 100,
        types: const [WasteType.metal], // 4.0 kg CO2e/kg
      );
      final cam = _req(
        status: RequestStatus.tamamlandi,
        confirmedKg: 100,
        types: const [WasteType.cam], // 0.3 kg CO2e/kg
      );

      expect(GreenPoints.forRequest(metal),
          greaterThan(GreenPoints.forRequest(cam)));
      // Oran, uydurma bir carpan degil karbon tablosunun kendisi
      expect(
        GreenPoints.forRequest(metal) / GreenPoints.forRequest(cam),
        closeTo(4.0 / 0.3, 0.01),
      );
    });

    test('coklu turde kilo turlere esit dagitilir (ImpactStats ile ayni)', () {
      final r = _req(
        status: RequestStatus.tamamlandi,
        confirmedKg: 100,
        types: const [WasteType.metal, WasteType.cam],
      );
      final expected = ((50 * 4.0) + (50 * 0.3)) * 10;
      expect(GreenPoints.forRequest(r), expected.round());
    });
  });

  group('Tesis seviyesi', () {
    test('esiklere gore dogru seviye', () {
      expect(FacilityTier.forPoints(0), FacilityTier.bronz);
      expect(FacilityTier.forPoints(1999), FacilityTier.bronz);
      expect(FacilityTier.forPoints(2000), FacilityTier.gumus);
      expect(FacilityTier.forPoints(8000), FacilityTier.altin);
      expect(FacilityTier.forPoints(50000), FacilityTier.platin);
    });

    test('en ust seviyenin sonraki seviyesi yok', () {
      expect(FacilityTier.platin.next, isNull);
      expect(FacilityTier.platin.progressTo(99999), 1);
    });

    test('ilerleme orani 0-1 arasinda kalir', () {
      // Gumus (2000) -> Altin (8000) arasi tam orta
      expect(FacilityTier.gumus.progressTo(5000), closeTo(0.5, 0.001));
    });
  });

  group('Cuzdan (turetilmis bakiye)', () {
    test('bakiye = kazanilan - harcanan', () {
      const w = PointsWallet(earned: 1000, spent: 300, confirmedDeliveries: 2);
      expect(w.balance, 700);
    });

    test('seviye HARCANANDAN degil KAZANILANDAN belirlenir', () {
      // Odul harcamak rozeti geri almamali
      const w = PointsWallet(earned: 8500, spent: 8000, confirmedDeliveries: 9);
      expect(w.tier, FacilityTier.altin);
      expect(w.balance, 500);
    });

    test('reddedilen talep puani geri birakir', () {
      // holdsPoints: reddedilen talep bakiyeden dusulmez
      expect(RedemptionStatus.beklemede.holdsPoints, isTrue);
      expect(RedemptionStatus.onaylandi.holdsPoints, isTrue);
      expect(RedemptionStatus.reddedildi.holdsPoints, isFalse);
    });
  });
}
