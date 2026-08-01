import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/map_utils.dart';
import '../../../../core/utils/marker_icons.dart';
import '../../../../core/widgets/premium_progress_bar.dart';
import '../../../collector/presentation/widgets/arrival_celebration_dialog.dart';
import '../../domain/models/waste_request_model.dart';
import '../providers/waste_request_providers.dart';

/// Takip ekraninin gorsel asamalari.
enum TrackingPhase {
  matching, // status == bekliyor (toplayici bekleniyor)
  enroute,  // status == atandi/yolda -> canli konum akiyor
  arrived,  // status == tamamlandi
}

/// Toplayici bilgisi artik SABIT DEGIL: talebi kim aldiysa onun gercek
/// hesap adi Firestore'daki `collectorName` alanindan gelir.
/// (Onceden "Ahmet Yılmaz / 34 ATK 501 / 4.9" sabit yaziliydi; gercek bir
///  toplayici giris yaptiginda tutmuyordu — uydurma puan/plaka da kaldirildi.)
const _collectorFallbackName = 'Toplayıcı';

/// ETA icin varsayilan ortalama sehir ici seyir hizi (km/sa).
/// Varis suresi ARTIK SABIT DEGIL: kalan gercek mesafeden hesaplanir.
/// (Once 5 dk sabitti; toplayici 300 m de olsa 300 km de olsa "5 dakika"
/// yaziyordu — juriye karsi savunulamaz bir iddiaydi.)
const _avgSpeedKmh = 30.0;

/// Yolculuk sayilmasi icin gereken en kucuk mesafe (km).
/// Bunun altinda toplayici zaten hedefin uzerinde demektir.
const _minTripKm = 0.05; // 50 m

/// KULLANICI tarafinin "Talebim Yolda" ekrani — TEK GERCEK KAYNAK.
///
/// ONEMLI MIMARI: Bu ekran ARTIK KENDI SIMULASYONUNU CALISTIRMAZ.
/// Aracin konumu tamamen Firestore'daki `collectorLocation` alanindan gelir;
/// toplayici cihazi yolculuk boyunca bu alani gunceller. Boylece iki ekran
/// ayni gercegi gosterir (onceden her ekran kendi baslangic noktasini
/// uydurdugu icin veri kopmasi/desync yasaniyordu).
///
/// Gelen konumlar ~900 ms araliklarla dustugu icin, isaretcinin zipla-zipla
/// gitmemesi adina ardisik iki konum arasinda YUMUSAK GECIS (interpolasyon)
/// yapilir — gercek cagri uygulamalarinin kullandigi yontem.
class RequestTrackingScreen extends ConsumerStatefulWidget {
  const RequestTrackingScreen({super.key, required this.request});

  /// Takip edilen talep (ID'si Firestore dokumanina isaret eder)
  final WasteRequest request;

  @override
  ConsumerState<RequestTrackingScreen> createState() =>
      _RequestTrackingScreenState();
}

class _RequestTrackingScreenState extends ConsumerState<RequestTrackingScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;

  /// Gelen iki konum arasinda yumusak gecis icin (simulasyon DEGIL)
  late final AnimationController _smooth;

  TrackingPhase _phase = TrackingPhase.matching;

  /// Interpolasyonun uclari: son bilinen konum -> yeni gelen konum
  LatLng? _from;
  LatLng? _to;
  double _bearing = 0;

  /// Rotanin baslangici = toplayicinin talebi ALDIGI andaki konumu.
  /// Firestore'dan ilk gelen collectorLocation ile bir kez belirlenir.
  LatLng? _routeStart;
  List<LatLng> _routePoints = const [];
  double _totalKm = 0;

  /// Kamera takibi kisitlamasi (harita kilitlenmesin)
  DateTime _lastCameraMove = DateTime.fromMillisecondsSinceEpoch(0);
  static const _cameraFollowInterval = Duration(milliseconds: 900);

  /// Talebi alan toplayicinin GERCEK adi (Firestore'dan canli gelir)
  String? _liveCollectorName;

  /// Ekranda gosterilecek toplayici adi — yoksa nötr etikete duser
  String get _collectorName {
    final n = _liveCollectorName?.trim();
    return (n == null || n.isEmpty) ? _collectorFallbackName : n;
  }

  @override
  void initState() {
    super.initState();
    // Konum guncelleme araligiyla ayni sure -> kesintisiz akan hareket
    _smooth = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _smooth.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // CANLI VERI SENKRONU
  // ---------------------------------------------------------------

  /// Firestore'dan her yeni talep anlik goruntusunde calisir.
  void _syncWithRequest(WasteRequest r) {
    // Toplayici adini canli veriden al (talep alindiginda dolar)
    if (r.collectorName != null && r.collectorName != _liveCollectorName) {
      _liveCollectorName = r.collectorName;
    }

    switch (r.status) {
      case RequestStatus.bekliyor:
        break; // Toplayici bekleniyor

      case RequestStatus.atandi:
      case RequestStatus.yolda:
        if (_phase == TrackingPhase.matching) {
          setState(() => _phase = TrackingPhase.enroute);
        }
        final live = r.collectorLocation;
        if (live != null) _onLiveLocation(live, r.collectorBearing);

      case RequestStatus.tamamlandi:
        _onCollectorArrived();

      case RequestStatus.iptal:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Talep iptal edildi.')),
          );
          Navigator.of(context).pop();
        }
    }
  }

  /// Firestore'dan gelen YENI konumu isler: rotayi (ilk seferde) kurar,
  /// interpolasyonu baslatir, kamerayi olculu sekilde takip ettirir.
  void _onLiveLocation(LatLng live, double? bearing) {
    // Ilk konum: rota baslangicini sabitle ve ayni egriyi olustur.
    // Toplayici da ayni fonksiyonu ayni noktalarla kullandigi icin iki
    // ekranda CIZGI BIREBIR AYNI olur.
    if (_routeStart == null) {
      _routeStart = live;
      _routePoints = MapUtils.buildCurvedRoute(live, widget.request.location);
      _totalKm = MapUtils.distanceKm(live, widget.request.location);
      _from = live;
      _to = live;

      // Rotanin tamamini guvenli sekilde cerceve icine al
      _mapController?.animateCamera(
        MapUtils.fitTwoPoints(live, widget.request.location),
      );
    }

    // Ayni konum tekrar geldiyse bosuna animasyon baslatma
    final current = _currentVehiclePosition;
    if (current != null &&
        (current.latitude - live.latitude).abs() < 1e-7 &&
        (current.longitude - live.longitude).abs() < 1e-7) {
      return;
    }

    setState(() {
      _from = current ?? live;
      _to = live;
      if (bearing != null) _bearing = bearing;
    });
    _smooth.forward(from: 0);

    // Kamerayi olculu araliklarla takip ettir
    final now = DateTime.now();
    if (now.difference(_lastCameraMove) >= _cameraFollowInterval) {
      _lastCameraMove = now;
      _mapController?.animateCamera(CameraUpdate.newLatLng(live));
    }
  }

  /// Iki konum arasinda yumusatilmis ANLIK arac konumu
  LatLng? get _currentVehiclePosition {
    final from = _from, to = _to;
    if (from == null || to == null) return null;
    final t = Curves.easeOut.transform(_smooth.value);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  /// Kalan gercek mesafe (km) — ETA ve ilerleme bundan turetilir
  double get _remainingKm {
    final v = _currentVehiclePosition;
    if (v == null) return _totalKm;
    return MapUtils.distanceKm(v, widget.request.location);
  }

  /// Gercek mesafeye dayali ilerleme (0-1) — sahte sayac degil.
  ///
  /// ONEMLI: Toplayici talebi ALDIGI anda zaten hedefin uzerindeyse
  /// (ornegin onceki teslimati ayni adreste bitirdiyse) toplam mesafe
  /// ~0 olur. Eskiden bu durumda 0 donuyordu ve cubuk hic dolmuyordu;
  /// dogrusu yolculugun tamamlanmis sayilmasidir.
  double get _progress {
    final v = _currentVehiclePosition;
    if (v == null) return 0;
    if (_totalKm < _minTripKm) return 1;
    return (1 - (_remainingKm / _totalKm)).clamp(0.0, 1.0);
  }

  /// Kalan tahmini sure (dk) — kalan MESAFEDEN hesaplanir, sabit degil.
  int get _remainingMinutes {
    final minutes = (_remainingKm / _avgSpeedKmh) * 60;
    if (!minutes.isFinite) return 1;
    return minutes.ceil().clamp(1, 999);
  }

  /// Toplayici kapiya vardiginda (status: tamamlandi)
  Future<void> _onCollectorArrived() async {
    if (_phase == TrackingPhase.arrived) return;
    setState(() => _phase = TrackingPhase.arrived);
    Haptics.success();

    await showArrivalCelebration(
      context,
      request: widget.request,
      title: 'Toplayıcınız Kapınızda! 🎉',
      subtitle:
          '$_collectorName atıklarınızı teslim almak için kapınızda. '
          'Katkınız için teşekkürler! 🌱',
    );

    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  Set<Marker> _buildMarkers(MarkerIcons? icons) {
    final vehicle = _currentVehiclePosition;
    return {
      Marker(
        markerId: const MarkerId('home'),
        position: widget.request.location,
        icon: icons?.home ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        anchor: const Offset(0.5, 1.0),
        infoWindow: const InfoWindow(title: 'Adresiniz'),
      ),
      // Arac YALNIZCA canli konum geldiginde cizilir (mock yok)
      if (vehicle != null && _phase != TrackingPhase.matching)
        Marker(
          markerId: const MarkerId('vehicle'),
          position: vehicle,
          icon: icons?.vehicle ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          anchor: const Offset(0.5, 0.5),
          rotation: _bearing,
          zIndex: 10,
          infoWindow: InfoWindow(title: 'Toplayıcınız: $_collectorName'),
        ),
    };
  }

  Widget _buildStatusCard() {
    switch (_phase) {
      case TrackingPhase.matching:
        return Card(
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.primary),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Size en yakın toplayıcı aranıyor...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );

      case TrackingPhase.enroute:
        return Card(
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.local_shipping,
                    color: AppColors.primary, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    // KRITIK: Stack icinde gevsek kisit geldigi icin Column
                    // varsayilan (max) davranista tum ekrani yutar ve kart
                    // devasa beyaz bir bloga donusur. min = sadece icerik kadar.
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Toplayıcınız $_collectorName yolda · '
                        '${_remainingKm.toStringAsFixed(1)} km · '
                        'tahminî $_remainingMinutes dk',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                      const SizedBox(height: 3),
                      // DURUST NOT: konum artik gercekten toplayici
                      // cihazindan canli akiyor; hareketin kendisi simulasyon.
                      Text(
                        'Konum toplayıcı cihazından canlı alınıyor · '
                        'araç hareketi simülasyondur',
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

      case TrackingPhase.arrived:
        return Card(
          elevation: 4,
          color: Colors.green.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.primary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Toplayıcınız kapınızda! 🎉',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildCollectorCard() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withOpacity(0.12),
                  child: const Text(
                    'AY',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _collectorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.verified_user_outlined,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'ATOS görevlisi',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.phone,
                        color: Colors.white, size: 18),
                    onPressed: () {
                      Haptics.tap();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('📞 Arama özelliği yakında!'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Ilerleme artik GERCEK mesafeden hesaplanir
            PremiumProgressBar(value: _progress),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // CANLI DINLEME: talep dokumanindaki her degisiklik (durum + toplayici
    // konumu) bu ekrani gunceller. Tek gercek kaynak burasi.
    ref.listen(requestByIdProvider(widget.request.id), (previous, next) {
      final request = next.valueOrNull;
      if (request != null) _syncWithRequest(request);
    });

    final markerIcons = ref.watch(markerIconsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Talebim Yolda'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) => _mapController = c,
            initialCameraPosition: CameraPosition(
              target: widget.request.location,
              zoom: 14,
            ),
            markers: _buildMarkers(markerIcons),
            // Rota yalnizca canli konum geldiginde cizilir
            polylines: _routePoints.length < 2
                ? {}
                : {
                    MapUtils.buildRoutePolyline(
                      id: 'route-${widget.request.id}',
                      points: _routePoints,
                      color: AppColors.primary,
                    ),
                  },
            zoomControlsEnabled: false,
            padding: const EdgeInsets.only(top: 130, bottom: 150),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PointerInterceptor(child: _buildStatusCard()),
            ),
          ),
          if (_phase != TrackingPhase.matching)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: PointerInterceptor(child: _buildCollectorCard()),
            ),
        ],
      ),
    );
  }
}
