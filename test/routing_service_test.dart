// GERCEK YOL ROTASI (Google Routes API) — cozumleme, GIZLILIK ve
// GERI DUSME testleri.
//
// Bu testler AGA CIKMAZ: ag cagrisi disaridan verilebilen bir fonksiyon
// oldugu icin basarili yanit, bozuk yanit, zaman asimi ve servis
// coktu gibi durumlarin hepsi burada deterministik olarak uretilir.
//
// Iki kritik davranis:
//   1. HER hata durumunda eski davranisa (kavisli cizgi) dusulmesi.
//      Yol rotasi bir IYILESTIRMEDIR; gelmezse sistem calismaya devam
//      etmeli, asla kilitlenmemeli.
//   2. GIZLILIK: koordinatlar URL'e KONMAMALI. Eskiden OSRM'in demo
//      sunucusuna URL yolunda gidiyorlardi ve ucuncu tarafin erisim
//      loglarina dusuyorlardi. Asagidaki testler bunun geri gelmesini
//      engeller.
import 'dart:convert';

import 'package:atik_toplama_app/core/utils/map_utils.dart';
import 'package:atik_toplama_app/core/utils/routing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _from = LatLng(39.6094, 32.1798);
const _to = LatLng(39.5730, 32.1450);

/// Routes API'nin gercek yanit bicimi (kisaltilmis)
const _basariliYanit = '''
{"routes":[{"polyline":{"geoJsonLinestring":{"type":"LineString",
"coordinates":[
[32.182425,39.608452],[32.180100,39.605300],[32.170050,39.590120],
[32.150900,39.578400],[32.144631,39.572944]]}}}]}
''';

/// Testler her zaman anahtarli kurulur — aksi halde servis kendini
/// devre disi birakir ve fetcher hic cagrilmaz (bkz. "anahtar yok" testi).
RoutingService _servis(RouteFetcher f, {Duration? timeout}) => RoutingService(
      fetcher: f,
      apiKey: 'test-anahtari',
      timeout: timeout ?? const Duration(seconds: 4),
    );

void main() {
  _guzergahTestleri();
  _gizlilikTestleri();
  setUp(RoutingService.clearCache);

  group('Yanit cozumleme', () {
    test('koordinatlar [boylam,enlem] -> LatLng(enlem,boylam) cevrilir', () {
      final p = RoutingService.parseRoute(_basariliYanit);
      expect(p.length, 5);
      // GeoJSON boylami ONCE verir; ters cevirmezsek arac Afrika'da cikar
      expect(p.first.latitude, closeTo(39.608452, 1e-6));
      expect(p.first.longitude, closeTo(32.182425, 1e-6));
      expect(p.last.latitude, closeTo(39.572944, 1e-6));
    });

    test('rota bulunamazsa (bos nesne) istisna atar', () {
      expect(() => RoutingService.parseRoute('{}'),
          throwsA(isA<FormatException>()));
      expect(() => RoutingService.parseRoute('{"routes":[]}'),
          throwsA(isA<FormatException>()));
    });

    test('bozuk JSON istisna atar', () {
      expect(() => RoutingService.parseRoute('bu json degil'),
          throwsA(anything));
    });

    test('geometrisi olmayan yanit istisna atar', () {
      expect(
        () => RoutingService.parseRoute('{"routes":[{}]}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('bozuk koordinatlar ayiklanir, saglamlar kalir', () {
      final p = RoutingService.parseRoute(
        '{"routes":[{"polyline":{"geoJsonLinestring":{"coordinates":'
        '[[32.1,39.6],["a","b"],[32.2],[32.3,39.7]]}}}]}',
      );
      expect(p.length, 2);
    });
  });

  group('Basarili yol rotasi', () {
    test('gercek yol noktalari dondurulur', () async {
      final r = await _servis((_, __, ___) async => _basariliYanit)
          .roadRoute(_from, _to);
      expect(r.length, 5);
      expect(r.first.latitude, closeTo(39.608452, 1e-6));
    });

    test('istek Routes API bicimine uygun kurulur', () async {
      late Uri cagrilan;
      late String govde;
      late Map<String, String> basliklar;
      await _servis((u, b, h) async {
        cagrilan = u;
        govde = b;
        basliklar = h;
        return _basariliYanit;
      }).roadRoute(_from, _to);

      expect(cagrilan.host, 'routes.googleapis.com');
      expect(cagrilan.path, contains('computeRoutes'));
      expect(basliklar['X-Goog-Api-Key'], 'test-anahtari');
      expect(basliklar['X-Goog-FieldMask'], contains('geoJsonLinestring'));

      final j = jsonDecode(govde) as Map<String, dynamic>;
      expect(j['travelMode'], 'DRIVE');
      expect(j['polylineEncoding'], 'GEO_JSON_LINESTRING');
      expect(j['origin']['location']['latLng']['latitude'],
          closeTo(39.6094, 1e-6));
      expect(j['destination']['location']['latLng']['longitude'],
          closeTo(32.1450, 1e-6));
      // Iki noktali rotada ara durak OLMAMALI
      expect(j.containsKey('intermediates'), isFalse);
    });

    test('ayni rota ikinci kez istenirse AGA CIKILMAZ (onbellek)', () async {
      var cagriSayisi = 0;
      final s = _servis((_, __, ___) async {
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
      final r = await _servis((_, __, ___) async => throw Exception('ag yok'))
          .roadRoute(_from, _to);
      expect(r.length, kavisliUzunluk);
    });

    test('ZAMAN ASIMINDA duser ve BEKLEMEDE KALMAZ', () async {
      final s = _servis(
        (_, __, ___) =>
            Future.delayed(const Duration(seconds: 30), () => _basariliYanit),
        timeout: const Duration(milliseconds: 120),
      );
      final basla = DateTime.now();
      final r = await s.roadRoute(_from, _to);
      final gecen = DateTime.now().difference(basla);

      expect(r.length, kavisliUzunluk);
      expect(gecen.inSeconds, lessThan(5),
          reason: 'zaman asimi calismali, cagri asilmamali');
    });

    test('servis rota bulamazsa duser', () async {
      final r =
          await _servis((_, __, ___) async => '{}').roadRoute(_from, _to);
      expect(r.length, kavisliUzunluk);
    });

    test('tek noktali (cizilemez) rota geldiginde duser', () async {
      final r = await _servis((_, __, ___) async =>
              '{"routes":[{"polyline":{"geoJsonLinestring":'
              '{"coordinates":[[32.1,39.6]]}}}]}')
          .roadRoute(_from, _to);
      expect(r.length, kavisliUzunluk);
    });

    test('geri dusulen rota da HER ZAMAN cizilebilir (>= 2 nokta)', () async {
      final r = await _servis((_, __, ___) async => throw Exception('kapali'))
          .roadRoute(_from, _to);
      expect(r.length, greaterThanOrEqualTo(2));
      // Rotanin ucu hedefe komsu olmali ki cizgi havada bitmesin
      expect(MapUtils.distanceKm(r.last, _to), lessThan(1.0));
    });
  });
}

// =====================================================================
// GIZLILIK — koordinat nereye gidiyor?
// =====================================================================
void _gizlilikTestleri() {
  group('GIZLILIK', () {
    setUp(RoutingService.clearCache);

    test('koordinatlar URL\'e KONMAZ (govdede gider)', () async {
      late Uri cagrilan;
      await _servis((u, _, __) async {
        cagrilan = u;
        return _basariliYanit;
      }).roadRoute(_from, _to);

      final tamUrl = cagrilan.toString();
      // Eskiden OSRM'e "32.1798,39.6094" seklinde URL YOLUNDA gidiyordu.
      // Ucuncu tarafin erisim loglarina dusmesin diye artik govdede.
      expect(tamUrl, isNot(contains('39.6')),
          reason: 'enlem URL\'de gorunmemeli');
      expect(tamUrl, isNot(contains('32.1')),
          reason: 'boylam URL\'de gorunmemeli');
      expect(cagrilan.query, isEmpty,
          reason: 'sorgu dizesinde hicbir sey tasinmamali');
    });

    test('ANAHTAR YOKSA aga HIC CIKILMAZ, kavisli cizgiye duser', () async {
      var cagri = 0;
      final s = RoutingService(
        apiKey: '', // anahtar tanimsiz
        fetcher: (_, __, ___) async {
          cagri++;
          return _basariliYanit;
        },
      );

      final r = await s.roadRoute(_from, _to);
      expect(cagri, 0, reason: 'anahtarsiz ag cagrisi yapilmamali');
      expect(r.length, MapUtils.buildCurvedRoute(_from, _to).length);
    });

    test('anahtar URL\'e degil BASLIGA konur', () async {
      late Uri cagrilan;
      late Map<String, String> basliklar;
      await _servis((u, _, h) async {
        cagrilan = u;
        basliklar = h;
        return _basariliYanit;
      }).roadRoute(_from, _to);

      expect(cagrilan.toString(), isNot(contains('test-anahtari')));
      expect(basliklar['X-Goog-Api-Key'], 'test-anahtari');
    });
  });
}

// =====================================================================
// COK DURAKLI GUZERGAH — akilli toplama rotasi
// =====================================================================
void _guzergahTestleri() {
  const a = LatLng(39.61, 32.18);
  const b = LatLng(39.59, 32.16);
  const c = LatLng(39.57, 32.14);

  group('roadRouteVia', () {
    setUp(RoutingService.clearCache);

    test('TEK istekle tum duraklar gonderilir', () async {
      var cagri = 0;
      late String govde;
      await _servis((_, g, __) async {
        cagri++;
        govde = g;
        return _basariliYanit;
      }).roadRouteVia([a, b, c]);

      expect(cagri, 1, reason: 'her bacak icin ayri istek atilmamali');

      final j = jsonDecode(govde) as Map<String, dynamic>;
      expect(j['origin']['location']['latLng']['latitude'], closeTo(39.61, 1e-6));
      expect(
          j['destination']['location']['latLng']['latitude'], closeTo(39.57, 1e-6));
      // Ortadaki durak ARA DURAK olarak gitmeli
      final ara = j['intermediates'] as List;
      expect(ara.length, 1);
      expect(ara.first['location']['latLng']['latitude'], closeTo(39.59, 1e-6));
    });

    test('basarili yanitta yol geometrisi doner', () async {
      final r = await _servis((_, __, ___) async => _basariliYanit)
          .roadRouteVia([a, b, c]);
      expect(r.length, 5);
    });

    test('HATA durumunda duraklarin KENDISI doner (duz cizgi)', () async {
      final r =
          await _servis((_, __, ___) async => throw Exception('servis kapali'))
              .roadRouteVia([a, b, c]);
      expect(r, [a, b, c], reason: 'cizgi kaybolmamali');
    });

    test('zaman asiminda da duz cizgiye duser', () async {
      final r = await _servis(
        (_, __, ___) =>
            Future.delayed(const Duration(seconds: 30), () => _basariliYanit),
        timeout: const Duration(milliseconds: 120),
      ).roadRouteVia([a, b, c]);
      expect(r, [a, b, c]);
    });

    test('tek nokta verilirse ag cagrisi YAPILMAZ', () async {
      var cagri = 0;
      final r = await _servis((_, __, ___) async {
        cagri++;
        return _basariliYanit;
      }).roadRouteVia([a]);
      expect(cagri, 0);
      expect(r, [a]);
    });
  });
}
