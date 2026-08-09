// GERCEK YOL ROTASI (OSRM) — cozumleme ve GERI DUSME testleri.
//
// Bu testler AGA CIKMAZ: ag cagrisi disaridan verilebilen bir fonksiyon
// oldugu icin basarili yanit, bozuk yanit, zaman asimi ve servis
// coktu gibi durumlarin hepsi burada deterministik olarak uretilir.
//
// En kritik davranis: HER hata durumunda eski davranisa (kavisli cizgi)
// dusulmesi. Yol rotasi bir IYILESTIRMEDIR; gelmezse sistem calismaya
// devam etmeli, asla kilitlenmemeli.
import 'package:atik_toplama_app/core/utils/map_utils.dart';
import 'package:atik_toplama_app/core/utils/routing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _from = LatLng(39.6094, 32.1798);
const _to = LatLng(39.5730, 32.1450);

/// OSRM'in gercek yanit bicimi (kisaltilmis)
const _basariliYanit = '''
{"code":"Ok","routes":[{"distance":5543.2,"duration":264.9,
"geometry":{"type":"LineString","coordinates":[
[32.182425,39.608452],[32.180100,39.605300],[32.170050,39.590120],
[32.150900,39.578400],[32.144631,39.572944]]}}]}
''';

RoutingService _servis(RouteFetcher f, {Duration? timeout}) => RoutingService(
      fetcher: f,
      timeout: timeout ?? const Duration(seconds: 4),
    );

void main() {
  setUp(RoutingService.clearCache);

  group('GeoJSON cozumleme', () {
    test('koordinatlar [boylam,enlem] -> LatLng(enlem,boylam) cevrilir', () {
      final p = RoutingService.parseGeoJson(_basariliYanit);
      expect(p.length, 5);
      // OSRM boylami ONCE verir; ters cevirmezsek arac Afrika'da cikar
      expect(p.first.latitude, closeTo(39.608452, 1e-6));
      expect(p.first.longitude, closeTo(32.182425, 1e-6));
      expect(p.last.latitude, closeTo(39.572944, 1e-6));
    });

    test('OSRM hata kodu dondururse istisna atar', () {
      expect(
        () => RoutingService.parseGeoJson('{"code":"NoRoute","routes":[]}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('bozuk JSON istisna atar', () {
      expect(() => RoutingService.parseGeoJson('bu json degil'),
          throwsA(anything));
    });

    test('geometrisi olmayan yanit istisna atar', () {
      expect(
        () => RoutingService.parseGeoJson('{"code":"Ok","routes":[{}]}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('bozuk koordinatlar ayiklanir, saglamlar kalir', () {
      final p = RoutingService.parseGeoJson(
        '{"code":"Ok","routes":[{"geometry":{"coordinates":'
        '[[32.1,39.6],["a","b"],[32.2],[32.3,39.7]]}}]}',
      );
      expect(p.length, 2);
    });
  });

  group('Basarili yol rotasi', () {
    test('gercek yol noktalari dondurulur', () async {
      final r = await _servis((_) async => _basariliYanit)
          .roadRoute(_from, _to);
      expect(r.length, 5);
      expect(r.first.latitude, closeTo(39.608452, 1e-6));
    });

    test('istek OSRM bicimine uygun kurulur (boylam,enlem sirasi)', () async {
      late Uri cagrilan;
      await _servis((u) async {
        cagrilan = u;
        return _basariliYanit;
      }).roadRoute(_from, _to);

      expect(cagrilan.host, 'router.project-osrm.org');
      expect(cagrilan.path, contains('32.1798,39.6094'));
      expect(cagrilan.path, contains('32.145,39.573'));
      expect(cagrilan.query, contains('geometries=geojson'));
    });

    test('ayni rota ikinci kez istenirse AGA CIKILMAZ (onbellek)', () async {
      var cagriSayisi = 0;
      final s = _servis((_) async {
        cagriSayisi++;
        return _basariliYanit;
      });
      await s.roadRoute(_from, _to);
      await s.roadRoute(_from, _to);
      expect(cagriSayisi, 1);
    });
  });

  group('GERI DUSME — sistem asla kilitlenmez', () {
    // Kavisli cizginin nokta sayisi sabittir; geri dusuldugunu bundan
    // anliyoruz.
    final kavisliUzunluk = MapUtils.buildCurvedRoute(_from, _to).length;

    test('ag hatasinda kavisli cizgiye duser', () async {
      final r = await _servis((_) async => throw Exception('ag yok'))
          .roadRoute(_from, _to);
      expect(r.length, kavisliUzunluk);
    });

    test('ZAMAN ASIMINDA duser ve BEKLEMEDE KALMAZ', () async {
      final s = _servis(
        (_) => Future.delayed(const Duration(seconds: 30), () => _basariliYanit),
        timeout: const Duration(milliseconds: 120),
      );
      final basla = DateTime.now();
      final r = await s.roadRoute(_from, _to);
      final gecen = DateTime.now().difference(basla);

      expect(r.length, kavisliUzunluk);
      expect(gecen.inSeconds, lessThan(5),
          reason: 'zaman asimi calismali, cagri asilmamali');
    });

    test('servis hata kodu dondururse duser', () async {
      final r = await _servis((_) async => '{"code":"NoRoute","routes":[]}')
          .roadRoute(_from, _to);
      expect(r.length, kavisliUzunluk);
    });

    test('tek noktali (cizilemez) rota geldiginde duser', () async {
      final r = await _servis((_) async =>
              '{"code":"Ok","routes":[{"geometry":{"coordinates":[[32.1,39.6]]}}]}')
          .roadRoute(_from, _to);
      expect(r.length, kavisliUzunluk);
    });

    test('geri dusulen rota da HER ZAMAN cizilebilir (>= 2 nokta)', () async {
      final r = await _servis((_) async => throw Exception('kapali'))
          .roadRoute(_from, _to);
      expect(r.length, greaterThanOrEqualTo(2));
      // Rotanin ucu hedefe komsu olmali ki cizgi havada bitmesin
      expect(MapUtils.distanceKm(r.last, _to), lessThan(1.0));
    });
  });
}
