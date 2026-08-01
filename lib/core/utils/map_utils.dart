import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Rota uzerindeki bir animasyon karesinin sonucu:
/// aracin anlik konumu ve bakmasi gereken yon.
typedef RoutePosition = ({LatLng position, double bearing});

/// Harita/rota hesaplamalari icin ortak yardimci fonksiyonlar.
///
/// Hem Toplayici ekrani hem Kullanici "Talebim Yolda" ekrani
/// ayni simulasyon mantigini buradan kullanir — kod tekrari yoktur.
class MapUtils {
  MapUtils._(); // Sadece statik kullanim

  /// Iki koordinat arasindaki pusula yonunu (bearing) derece dondurur.
  /// 0 = kuzey, 90 = dogu. Marker'in rotation degeri olarak kullanilir.
  static double bearingBetween(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Baslangic-bitis arasina sinus kavisli ara noktalar ekleyerek
  /// "yol gibi" gorunen simule rota noktalari uretir.
  ///
  /// Ayni nokta listesi hem polyline cizimi hem pin animasyonu icin
  /// kullanilmalidir; boylece arac cizginin tam ustunde hareket eder.
  /// [segments] arttikca animasyon daha akici olur.
  static List<LatLng> buildCurvedRoute(
    LatLng start,
    LatLng end, {
    int segments = 40,
    double curveHeight = 0.0012,
  }) {
    final points = <LatLng>[];
    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      final lat = start.latitude + (end.latitude - start.latitude) * t;
      final lng = start.longitude + (end.longitude - start.longitude) * t;
      // Ortada max olan yumusak sapma (parabol) — kavis efekti
      final curve = curveHeight * (1 - (2 * t - 1) * (2 * t - 1));
      points.add(LatLng(lat + curve, lng));
    }
    return points;
  }

  /// Rota uzerinde [t] (0.0-1.0) ilerlemesine denk gelen konumu ve
  /// o andaki hareket yonunu hesaplar.
  ///
  /// Animasyonun her karesinde cagrilir: rota N noktadan olusur,
  /// t degeri once ilgili segmente, sonra segment icindeki orana cevrilir
  /// ve dogrusal interpolasyon ile ara konum bulunur.
  static RoutePosition positionOnRoute(List<LatLng> points, double t) {
    assert(points.length >= 2, 'Rota en az 2 nokta icermelidir');

    final totalSegments = points.length - 1;
    final rawIndex = (t.clamp(0.0, 1.0)) * totalSegments;
    final segIndex = rawIndex.floor().clamp(0, totalSegments - 1);
    final segT = rawIndex - segIndex; // Segment icindeki oran (0-1)

    final from = points[segIndex];
    final to = points[segIndex + 1];

    final position = LatLng(
      from.latitude + (to.latitude - from.latitude) * segT,
      from.longitude + (to.longitude - from.longitude) * segT,
    );

    return (position: position, bearing: bearingBetween(from, to));
  }

  /// Iki noktayi birden gosterecek GUVENLI kamera sinirlari.
  ///
  /// KRITIK: Iki nokta ayni veya cok yakinsa olusan "dejenere" (sifir alanli)
  /// kutu, newLatLngBounds'u sonsuz zoom'a sokar ve harita bembeyaz kalir.
  /// Bu yuzden minimum bir aralik ([minSpan] derece) garanti ediyoruz ve
  /// degerleri gecerli enlem/boylam sinirlarina kirpiyoruz.
  /// SW her zaman (min enlem, min boylam), NE her zaman (max, max).
  /// [minSpan] varsayilani ~0.018 derece (~2 km) secildi: hem dejenere
  /// kutuyu engeller hem de noktalar birbirine cok yakinken kameranin
  /// asiri yakinlasmasini onleyip FERAH, tutarli bir cerceve verir.
  static LatLngBounds boundsFor(LatLng a, LatLng b, {double minSpan = 0.018}) {
    var south = math.min(a.latitude, b.latitude);
    var north = math.max(a.latitude, b.latitude);
    var west = math.min(a.longitude, b.longitude);
    var east = math.max(a.longitude, b.longitude);

    // Dejenere/cok dar kutuyu merkezinden genislet
    if (north - south < minSpan) {
      final center = (north + south) / 2;
      south = center - minSpan / 2;
      north = center + minSpan / 2;
    }
    if (east - west < minSpan) {
      final center = (east + west) / 2;
      west = center - minSpan / 2;
      east = center + minSpan / 2;
    }

    // Gecerli aralik disina tasmayi engelle
    south = south.clamp(-85.0, 85.0);
    north = north.clamp(-85.0, 85.0);
    west = west.clamp(-180.0, 180.0);
    east = east.clamp(-180.0, 180.0);

    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  /// Iki noktayi ekrana sigdirmak icin GUVENLI ve TUTARLI kamera guncellemesi.
  ///
  /// Tum ekranlar (Toplayici + Takip) BU tek fonksiyonu kullanir; boylece
  /// cerceveleme her yerde birebir ayni olur.
  ///
  /// - [boundsFor] minimum ~2 km'lik bir kutu garanti ettigi icin, noktalar
  ///   birbirine cok yakin olsa bile kamera asiri yakinlasmaz (eski sabit
  ///   "zoom 16" fallback'i kaldirildi — asimetrinin sebebi oydu).
  /// - Koordinatlar bozuksa (NaN/sonsuz) guvenli bir varsayilana duser.
  static CameraUpdate fitTwoPoints(
    LatLng a,
    LatLng b, {
    double padding = 60,
  }) {
    final valid = a.latitude.isFinite &&
        a.longitude.isFinite &&
        b.latitude.isFinite &&
        b.longitude.isFinite;
    if (!valid) {
      return CameraUpdate.newLatLngZoom(a, 14);
    }
    return CameraUpdate.newLatLngBounds(boundsFor(a, b), padding);
  }

  /// Iki koordinat arasindaki kus ucusu mesafeyi km olarak dondurur.
  /// (Haversine formulu — harici pakete gerek birakmaz.)
  static double distanceKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;

    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * earthRadiusKm * math.asin(math.sqrt(h));
  }

  /// Standart "tahmini rota" gorunumlu kesikli polyline uretir.
  /// Iki ekranda da ayni gorsel dil kullanilsin diye tek yerden cikar.
  static Polyline buildRoutePolyline({
    required String id,
    required List<LatLng> points,
    required Color color,
  }) {
    return Polyline(
      polylineId: PolylineId(id),
      points: points,
      color: color,
      width: 5,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );
  }
}
