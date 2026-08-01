import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../features/waste_request/domain/models/waste_request_model.dart';
import 'map_utils.dart';

/// Optimize edilmis cok duraklı rotanin sonucu.
class OptimizedRoute {
  const OptimizedRoute({
    required this.orderedStops,
    required this.totalDistanceKm,
    required this.pathPoints,
  });

  /// Ziyaret sirasina gore siralanmis talepler
  final List<WasteRequest> orderedStops;

  /// Toplam guzergah uzunlugu (km) — baslangictan son duraga
  final double totalDistanceKm;

  /// Polyline cizimi icin nokta dizisi: [baslangic, durak1, durak2, ...]
  final List<LatLng> pathPoints;

  int get stopCount => orderedStops.length;
}

/// Toplayici icin cok duraklı toplama rotasi optimizasyonu.
///
/// "En Yakin Komsu" (Nearest Neighbor) sezgisel algoritmasi:
/// Gezgin Satici Problemi'nin (TSP) hizli, pratik bir yaklasimidir.
/// Her adimda, bulunulan noktadan en yakin ZIYARET EDILMEMIS duraga
/// gidilir; boylece toplayicinin kat edecegi toplam mesafe kabaca
/// minimize edilir (optimuma yakin, O(n^2) karmasiklikta).
///
/// Gercek bir hesaplamadir — "AI ile optimize edildi" rozeti bu
/// algoritmanin arkasinda durur, gorsel bir suslemeye dayanmaz.
class RouteOptimizer {
  RouteOptimizer._();

  /// [start] konumundan baslayarak [requests] taleplerini en yakin
  /// komsu sirasiyla dizer ve toplam mesafeyi hesaplar.
  static OptimizedRoute nearestNeighbor(
    LatLng start,
    List<WasteRequest> requests,
  ) {
    // Girdi listesini bozmamak icin kopya uzerinde calis
    final remaining = List<WasteRequest>.from(requests);
    final ordered = <WasteRequest>[];
    final path = <LatLng>[start];

    var current = start;
    var total = 0.0;

    // Her turda kalan duraklar arasindan en yakinini sec
    while (remaining.isNotEmpty) {
      var bestIndex = 0;
      var bestDistance = double.infinity;

      for (var i = 0; i < remaining.length; i++) {
        final d = MapUtils.distanceKm(current, remaining[i].location);
        if (d < bestDistance) {
          bestDistance = d;
          bestIndex = i;
        }
      }

      // En yakin duragi rotaya ekle ve oraya "tasin"
      final next = remaining.removeAt(bestIndex);
      ordered.add(next);
      path.add(next.location);
      total += bestDistance;
      current = next.location;
    }

    return OptimizedRoute(
      orderedStops: ordered,
      totalDistanceKm: total,
      pathPoints: path,
    );
  }
}
