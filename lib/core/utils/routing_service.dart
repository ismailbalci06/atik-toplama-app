import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'map_utils.dart';

/// Ag cagrisini disaridan verilebilir kilan imza — testler ag'a CIKMAZ.
typedef RouteFetcher = Future<String> Function(
  Uri uri,
  String body,
  Map<String, String> headers,
);

/// GERCEK YOL ROTASI — Google Routes API (`v2:computeRoutes`) ile.
///
/// NEDEN OSRM DEGIL (degistirildi):
/// Eskiden `router.project-osrm.org` kullaniliyordu. O, OSRM projesinin
/// HERKESE ACIK DEMO sunucusu ve rota istegi koordinatlari URL YOLUNA
/// koyuyordu. Yani kullanicinin EV KOORDINATI ucuncu bir tarafin erisim
/// loglarina dusuyordu. Dahasi `roadRouteVia` bir toplayicinin TUM
/// vardiyasini tek URL'de gonderiyordu: birbiriyle iliskilendirilmis bir
/// adres listesi. Bu, `firestore.rules`'un acik adresi `private/detail`
/// alt dokumaninda saklama cabasiyla celisiyordu.
///
/// NEDEN ESKIDEN OSRM SECILMISTI: Google'in ESKI Directions REST ucu
/// (`maps.googleapis.com/maps/api/directions/json`) tarayici kaynakli
/// isteklere CORS izni VERMEZ; Flutter Web'den cagrilamaz. Bu dogruydu.
///
/// NEDEN ARTIK GOOGLE: Yeni Routes API CORS DESTEKLIYOR — `Origin`
/// basligini yansitiyor ve `X-Goog-Api-Key` basligina izin veriyor, yani
/// tarayicidan cagrilabiliyor. Ustelik POST oldugu icin koordinatlar
/// URL'de degil GOVDEDE gider; erisim loglarina dusmez. Anahtar zaten
/// HTTP referrer ile kisitli (web.app, firebaseapp.com, localhost:5858).
///
/// ANAHTAR NEREDEN GELIYOR: Derleme aninda `--dart-define=MAPS_API_KEY=...`
/// ile; `tool/build_web.sh` bunu `.maps_api_key` dosyasindan okuyup gecirir.
/// Anahtar YOKSA ag cagrisi HIC YAPILMAZ, dogrudan kavisli cizgiye dusulur.
///
/// TASARIM — ASLA KILITLENMEZ (degismedi):
/// Her cagri kisa bir zaman asimiyla sinirlidir ve HER hata (zaman asimi,
/// ag kopmasi, bozuk yanit, anahtar yok, kota bitti) tek bir yere duser:
/// eski davranisa, yani [MapUtils.buildCurvedRoute] ile cizilen kavisli
/// cizgiye. Yani gercek rota bir IYILESTIRMEDIR; gelmezse sistem bugunku
/// haliyle calismaya devam eder.
class RoutingService {
  RoutingService({
    RouteFetcher? fetcher,
    this.timeout = const Duration(seconds: 4),
    String? apiKey,
  })  : _fetch = fetcher ?? _defaultFetch,
        _apiKey = apiKey ?? _envApiKey;

  final RouteFetcher _fetch;
  final String _apiKey;

  /// Ust sinir: demo sirasinda arac yola cikmadan once en fazla bu kadar
  /// bekleriz. Asilirsa kavisli cizgiye dusulur.
  final Duration timeout;

  /// Derleme aninda gomulen anahtar. Bos ise rota servisi devre disidir.
  static const _envApiKey = String.fromEnvironment('MAPS_API_KEY');

  /// Ayni iki nokta icin tekrar tekrar istek atmayi onler.
  /// Toplayici ekrani ve kullanicinin takip ekrani ayni rotayi ister;
  /// onbellek sayesinde servise tek istek gider.
  static final Map<String, List<LatLng>> _cache = {};

  static final _endpoint =
      Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes');

  /// Yalnizca cizgiyi istiyoruz — alan maskesi dar tutulur ki hem yanit
  /// kucuk olsun hem de ucret dusuk bantta kalsin.
  static const _fieldMask = 'routes.polyline.geoJsonLinestring';

  static Future<String> _defaultFetch(
    Uri uri,
    String body,
    Map<String, String> headers,
  ) async {
    final res = await http.post(uri, body: body, headers: headers);
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
      final points = await _iste([from, to]);
      if (points.length < 2) throw const FormatException('rota bos');

      _cache[key] = points;
      return points;
    } catch (e) {
      // Tek dusum noktasi: ne olursa olsun eski davranis.
      _uyar('Yol rotasi alinamadi, kavisli cizgiye dusuldu', e);
      return MapUtils.buildCurvedRoute(from, to);
    }
  }

  /// COK DURAKLI gercek yol rotasi (akilli toplama guzergahi icin).
  ///
  /// Routes API ara duraklari (`intermediates`) tek istekte kabul ettigi
  /// icin N duraklik guzergah TEK cagriyla alinir; her bacak icin ayri
  /// istek atmak hem yavas olurdu hem de gereksiz ucret cikarirdi.
  ///
  /// Hata durumunda [waypoints] listesinin KENDISI dondurulur — yani
  /// bugunku duz cizgi davranisi. Cizgi hicbir kosulda kaybolmaz.
  Future<List<LatLng>> roadRouteVia(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return waypoints;

    final key = waypoints.map(_coord).join(';');
    final onbellek = _cache[key];
    if (onbellek != null) return onbellek;

    try {
      final points = await _iste(waypoints);
      if (points.length < 2) throw const FormatException('rota bos');

      _cache[key] = points;
      return points;
    } catch (e) {
      _uyar('Guzergah alinamadi, duz cizgiye dusuldu', e);
      return waypoints;
    }
  }

  /// Routes API cagrisi. Anahtar yoksa AGA HIC CIKILMAZ.
  Future<List<LatLng>> _iste(List<LatLng> waypoints) async {
    if (_apiKey.isEmpty) {
      throw StateError(
        'MAPS_API_KEY tanimli degil — rota servisi devre disi. '
        'Derlemeyi tool/build_web.sh ile yapin.',
      );
    }

    final body = jsonEncode({
      'origin': _nokta(waypoints.first),
      'destination': _nokta(waypoints.last),
      if (waypoints.length > 2)
        'intermediates': [
          for (final w in waypoints.sublist(1, waypoints.length - 1))
            _nokta(w),
        ],
      'travelMode': 'DRIVE',
      // Kodlanmis polyline yerine GeoJSON: ayrica cozucu yazmak
      // gerekmesin diye. Fazladan kod = fazladan hata riski.
      'polylineEncoding': 'GEO_JSON_LINESTRING',
    });

    final yanit = await _fetch(_endpoint, body, {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': _apiKey,
      'X-Goog-FieldMask': _fieldMask,
    }).timeout(timeout);

    return parseRoute(yanit);
  }

  static Map<String, Object> _nokta(LatLng p) => {
        'location': {
          'latLng': {'latitude': p.latitude, 'longitude': p.longitude},
        },
      };

  /// Routes API yanitindan koordinat listesi cikarir.
  ///
  /// SAF fonksiyon: ag, zaman ve Firebase'e bagimli degildir — bu yuzden
  /// bozuk/eksik yanitlar dahil her durumu test edebiliyoruz.
  @visibleForTesting
  static List<LatLng> parseRoute(String body) {
    final json = jsonDecode(body);
    if (json is! Map) {
      throw const FormatException('Routes API yaniti gecersiz');
    }

    // Rota bulunamadiginda Routes API bos bir nesne doner: {}
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) {
      throw const FormatException('rota bulunamadi');
    }

    final coords =
        routes.first['polyline']?['geoJsonLinestring']?['coordinates'];
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

  /// Onbellek anahtari icin kisa koordinat bicimi.
  static String _coord(LatLng p) => '${p.longitude},${p.latitude}';

  /// Yalnizca gelistirme derlemesinde yazar: yayin derlemesinde
  /// `debugPrint` ayiklanmaz, bu yuzden kosul ACIKCA konur.
  static void _uyar(String mesaj, Object hata) {
    if (kDebugMode) debugPrint('🗺️ $mesaj: $hata');
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();
}
