import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'map_utils.dart';

/// Ag cagrisini disaridan verilebilir kilan imza — testler ag'a CIKMAZ.
typedef RouteFetcher = Future<String> Function(Uri uri);

/// GERCEK YOL ROTASI — OSRM (Open Source Routing Machine) ile.
///
/// NEDEN OSRM: Ucretsiz, anahtar gerektirmez ve tarayicidan cagrilabilir
/// (`access-control-allow-origin: *`). Google Directions API'nin REST ucu
/// tarayici kaynakli isteklere CORS izni VERMEZ; Flutter Web'de dogrudan
/// cagrilamaz. Bu yuzden tercih OSRM'dir.
///
/// TASARIM — ASLA KILITLENMEZ:
/// Her cagri kisa bir zaman asimiyla sinirlidir ve HER hata (zaman asimi,
/// ag kopmasi, bozuk yanit, servis kapali) tek bir yere duser: eski
/// davranisa, yani [MapUtils.buildCurvedRoute] ile cizilen kavisli
/// cizgiye. Yani gercek rota bir IYILESTIRMEDIR; gelmezse sistem
/// bugunku haliyle calismaya devam eder.
class RoutingService {
  RoutingService({
    RouteFetcher? fetcher,
    this.timeout = const Duration(seconds: 4),
  }) : _fetch = fetcher ?? _defaultFetch;

  final RouteFetcher _fetch;

  /// Ust sinir: demo sirasinda arac yola cikmadan once en fazla bu kadar
  /// bekleriz. Asilirsa kavisli cizgiye dusulur.
  final Duration timeout;

  /// Ayni iki nokta icin tekrar tekrar istek atmayi onler.
  /// Toplayici ekrani ve kullanicinin takip ekrani ayni rotayi ister;
  /// onbellek sayesinde servise tek istek gider.
  static final Map<String, List<LatLng>> _cache = {};

  static const _base = 'https://router.project-osrm.org/route/v1/driving';

  static Future<String> _defaultFetch(Uri uri) async {
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', uri);
    }
    // Turkce karakter iceren yol adlari icin UTF-8 zorunlu
    return utf8.decode(res.bodyBytes);
  }

  /// Iki nokta arasindaki GERCEK yol rotasi.
  ///
  /// Basarisiz olursa sessizce kavisli cizgiye duser — cagiran tarafin
  /// hata yonetmesi gerekmez, her zaman cizilebilir bir liste doner.
  Future<List<LatLng>> roadRoute(LatLng from, LatLng to) async {
    final key = _cacheKey(from, to);
    final onbellek = _cache[key];
    if (onbellek != null) return onbellek;

    try {
      // OSRM koordinati BOYLAM,ENLEM sirasiyla bekler (lat,lng DEGIL).
      final uri = Uri.parse(
        '$_base/${from.longitude},${from.latitude}'
        ';${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );

      final body = await _fetch(uri).timeout(timeout);
      final points = parseGeoJson(body);

      if (points.length < 2) throw const FormatException('rota bos');

      _cache[key] = points;
      return points;
    } catch (e) {
      // Tek dusum noktasi: ne olursa olsun eski davranis.
      debugPrint('🗺️ Yol rotasi alinamadi, kavisli cizgiye dusuldu: $e');
      return MapUtils.buildCurvedRoute(from, to);
    }
  }

  /// OSRM GeoJSON yanitindan koordinat listesi cikarir.
  ///
  /// SAF fonksiyon: ag, zaman ve Firebase'e bagimli degildir — bu yuzden
  /// bozuk/eksik yanitlar dahil her durumu test edebiliyoruz.
  /// GeoJSON tercih edildi cunku OSRM'in kodlanmis polyline bicimi ayrica
  /// cozucu yazmayi gerektirirdi; burada fazladan kod = fazladan hata riski.
  @visibleForTesting
  static List<LatLng> parseGeoJson(String body) {
    final json = jsonDecode(body);
    if (json is! Map || json['code'] != 'Ok') {
      throw FormatException('OSRM yaniti gecersiz: ${json is Map ? json['code'] : '?'}');
    }

    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) {
      throw const FormatException('rota bulunamadi');
    }

    final coords = routes.first['geometry']?['coordinates'];
    if (coords is! List) throw const FormatException('geometri yok');

    return coords
        .whereType<List>()
        .where((c) => c.length >= 2 && c[0] is num && c[1] is num)
        // GeoJSON sirasi [boylam, enlem] -> LatLng(enlem, boylam)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
  }

  /// Onbellek anahtari — koordinatlar ~11 m hassasiyete yuvarlanir.
  /// Aksi halde ondalik gurultusu yuzunden onbellek hic tutmazdi.
  static String _cacheKey(LatLng a, LatLng b) {
    String r(double v) => v.toStringAsFixed(4);
    return '${r(a.latitude)},${r(a.longitude)}'
        '->${r(b.latitude)},${r(b.longitude)}';
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();
}
