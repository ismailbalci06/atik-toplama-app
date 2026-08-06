import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/utils/map_utils.dart';
import '../../../../core/utils/marker_icons.dart';
import '../../../../core/utils/route_optimizer.dart';
import '../../../../core/widgets/premium_progress_bar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../reputation/presentation/providers/reputation_providers.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';
import '../../../waste_request/presentation/providers/waste_request_providers.dart';
import '../widgets/arrival_celebration_dialog.dart';
import '../widgets/confirm_weight_dialog.dart';
import '../widgets/request_detail_sheet.dart';

// NOT: Toplayici kimligi artik sabit degil — giris yapan kullanicinin
// gercek Firebase UID'si kullanilir (bkz. acceptRequest cagrisi).

/// Toplama aracinin DEPO (baslangic) konumu — Polatli'nin kuzeydogusu,
/// E90 cevre yolu yonu; test bolgesine yaklasik 4 km mesafede.
///
/// Demo hijyeni: talepler tarayici konumundan (Polatli merkez) dustugu icin
/// depo bilerek 3-5 km uzaga konuldu — rota hem kisa hem gorsel olarak sik
/// cikar. Arac her teslimattan sonra buraya doner (bkz. _onArrived), boylece
/// art arda yapilan demolarda her tur ayni temiz rotayla baslar.
/// Auth/GPS fazinda yerini gercek cihaz konumu alacak.
const _collectorStartLocation = LatLng(39.6094, 32.1798);

/// Toplayici (Gorevli) tarafinin ana harita ekrani — CANLI FIRESTORE VERISI.
///
/// - Pinler artik [pendingRequestsProvider] stream'inden gelir:
///   kullanici cihazinda talep olustugu ANDA burada pin belirir.
/// - "Talebi Al" -> repository.acceptRequest (transaction'li) calisir;
///   basarili olursa arac animasyonu baslar, varista talep Firestore'da
///   'tamamlandi' olarak isaretlenir.
/// - Baska toplayici talebi kapmissa kullaniciya hata mesaji gosterilir
///   ve pin stream sayesinde kendiliginden haritadan duser.
class CollectorMapScreen extends ConsumerStatefulWidget {
  const CollectorMapScreen({super.key});

  @override
  ConsumerState<CollectorMapScreen> createState() =>
      _CollectorMapScreenState();
}

class _CollectorMapScreenState extends ConsumerState<CollectorMapScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;

  /// Rota animasyonunu suren controller (0.0 -> 1.0 arasi ilerleme)
  late final AnimationController _tripController;

  /// Aracin anlik konumu/yonu — animasyon her karede gunceller
  LatLng _collectorPosition = _collectorStartLocation;
  double _collectorBearing = 0;

  /// Su an gidilen talep ve rotasi (yerel simulasyon durumu)
  List<LatLng> _activeRoutePoints = [];
  WasteRequest? _activeRequest;

  /// Aktif talebin TAM adresi — talep uzerimize alindiktan sonra korumali
  /// detay dokumanindan okunur. Alinmadan once bu deger YOKTUR; maske
  /// bu yuzden gercek bir maskedir, gorsel bir susleme degil.
  LatLng? _activeDestination;

  /// Aktif talebin hassas detayi (tam konum + kullanici notu).
  /// Firestore kurali bu dokumani yalnizca ATANMIS toplayiciya acar.
  RequestDetail? _activeDetail;

  /// Haritadaki aktif rota cizgisi
  final Set<Polyline> _polylines = {};

  /// Oturum ozeti (bellekte, sistemi hic yormaz): bu oturumda toplanan
  /// toplam kg ve teslimat sayisi. Her varista guncellenir.
  double _sessionKg = 0;
  int _sessionCount = 0;

  /// Kamera takibi kisitlamasi: her animasyon karesinde (60/sn) kamera
  /// oynatilirsa harita KILITLENIR ve kullanici haritayi kaydiramaz.
  /// Bu yuzden kamerayi en fazla ~800 ms'de bir yumusakca guncelliyoruz.
  DateTime _lastCameraMove = DateTime.fromMillisecondsSinceEpoch(0);
  static const _cameraFollowInterval = Duration(milliseconds: 800);

  /// Konumu Firestore'a yazma araligi. Her karede yazmak (60/sn) hem
  /// maliyetli hem gereksiz; ~900 ms yeterince akici bir canli takip verir.
  DateTime _lastLocationPush = DateTime.fromMillisecondsSinceEpoch(0);
  static const _locationPushInterval = Duration(milliseconds: 900);

  /// Maskeleme cemberinin yaricapi (metre). Konum izgarasi ~555 m
  /// oldugundan gercek nokta merkeze en fazla ~278 m uzaktadir; 500 m
  /// yaricap onu kesin kapsar ve icinde nerede oldugunu belli etmez.
  static const double _maskRadiusMeters = 500;

  /// Ust uste basarisiz olan konum yayini sayisi ve son hata metni.
  /// Sifirdan buyukse ekranda uyari seridi cikar — yayin sessizce
  /// kesilmesin, sorunu demo sirasinda ANINDA gorelim.
  int _failedPushes = 0;
  String? _lastPushError;

  /// Kesintiden sonra ayni gorevi tekrar tekrar surdurmeye calismayi onler
  String? _resumedRequestId;

  @override
  void initState() {
    super.initState();
    _tripController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )
      ..addListener(_onTripTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _onArrived();
      });
  }

  @override
  void dispose() {
    _tripController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // SIMULASYON (arac hareketi yerel; durum degisiklikleri Firestore'da)
  // ---------------------------------------------------------------

  /// Animasyonun HER karesinde calisir (saniyede ~60).
  ///
  /// DAYANIKLILIK: Govdenin tamami try/catch icinde. Buradan disari kacan
  /// tek bir istisna, saniyede 60 kez tekrarlanacagi icin ekrani kullanilamaz
  /// hale getirir. Hicbir kare hatasi yolculugu durdurmamali; hata olsa bile
  /// konsola basilip devam edilir.
  void _onTripTick() {
    try {
      if (_activeRoutePoints.length < 2) return;
      final t = Curves.easeInOut.transform(_tripController.value);
      final routePos = MapUtils.positionOnRoute(_activeRoutePoints, t);

      setState(() {
        _collectorPosition = routePos.position;
        _collectorBearing = routePos.bearing;
      });

      final now = DateTime.now();

      // Kamerayi HER KAREDE degil, araliklarla takip ettir (harita kilitlenmesin)
      if (now.difference(_lastCameraMove) >= _cameraFollowInterval) {
        _lastCameraMove = now;
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(routePos.position),
        );
      }

      // CANLI KONUM YAYINI: konumu Firestore'a yaz ki kullanicinin takip
      // ekrani ayni gercekligi gorsun (tek gercek kaynak).
      final active = _activeRequest;
      if (active != null &&
          now.difference(_lastLocationPush) >= _locationPushInterval) {
        _lastLocationPush = now;
        _pushLocation(active.id, routePos);
      }
    } catch (e, s) {
      // Kare basina hata: akisi KESME, sadece kaydet.
      debugPrint('🔥 Yolculuk karesi hatasi: ${readableError(e)}\n$s');
    }
  }

  /// Konum yayinini yapar ve BASARISIZLIGI GORUNUR kilar.
  ///
  /// Eskiden hata sessizce yutuluyordu: yayin kesilse bile toplayici bunu
  /// hicbir yerden anlamiyor, kullanicinin takip ekrani ise donuyordu.
  /// Artik ust uste basarisiz olan yayinlar ekranda bir uyari seridine
  /// donusuyor — demo sirasinda sorunu ANINDA gorursun.
  void _pushLocation(String requestId, RoutePosition routePos) {
    ref
        .read(wasteRequestRepositoryProvider)
        .updateCollectorLocation(
          requestId: requestId,
          position: routePos.position,
          bearing: routePos.bearing,
        )
        .then((_) {
      if (!mounted) return;
      if (_failedPushes != 0) setState(() => _failedPushes = 0);
    }).catchError((Object e) {
      logAndReadError(e, context: 'konum yayini');
      if (!mounted) return;
      setState(() {
        _failedPushes++;
        _lastPushError = readableError(e);
      });
    });
  }

  /// Arac hedefe varinca: Firestore'da talebi 'tamamlandi' yap + kutlama.
  /// Kullanici tarafi ayni dokumani dinledigi icin bu guncelleme
  /// karsi cihazda da aninda gorunur.
  Future<void> _onArrived() async {
    final arrivedRequest = _activeRequest;
    if (arrivedRequest == null) return;

    // --- MIKTAR ONAYI ---
    // Teslimat 'tamamlandi' olmadan ONCE toplayici gercek miktari onaylar.
    // Musterinin Yesil Puani yalnizca bu degerden dogar; beyan puan uretmez.
    final confirmedKg = await showConfirmWeightDialog(
      context,
      request: arrivedRequest,
    );
    // Diyalog kapatilamaz (barrierDismissible: false); yine de savunmaci ol
    if (confirmedKg == null || !mounted) return;

    setState(() {
      _polylines.clear();
      _activeRequest = null;
      _activeDestination = null; // teslimat bitti -> adres yeniden gizlenir
      _activeDetail = null;
      _activeRoutePoints = [];
      // Oturum ozeti ONAYLANAN miktardan hesaplanir (beyandan degil)
      _sessionKg += confirmedKg;
      _sessionCount++;
    });

    try {
      await ref.read(wasteRequestRepositoryProvider).completeRequest(
            requestId: arrivedRequest.id,
            confirmedKg: confirmedKg,
          );
    } catch (e) {
      // Yazma basarisiz olsa bile demo akisini kesme; sadece guvenli bildir
      final message = logAndReadError(e, context: 'completeRequest');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Durum güncellenemedi: $message')),
        );
      }
    }

    if (!mounted) return;
    Haptics.success(); // Varista basari titresimi
    await showArrivalCelebration(context, request: arrivedRequest);

    // --- Sefer kapandi: arac DEPOYA doner ---
    // Aksi halde arac teslimat adresinde park kalir; bir sonraki talep ayni
    // adresten geldiginde kat edilecek mesafe ~0 olur ve ortada gosterilecek
    // bir yolculuk kalmaz. Depoya donus, art arda yapilan demolarda her turun
    // ayni kisa ve duzenli rotayla baslamasini garanti eder.
    if (!mounted) return;
    setState(() {
      _collectorPosition = _collectorStartLocation;
      _collectorBearing = 0;
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_collectorStartLocation, 13),
    );
  }

  // ---------------------------------------------------------------
  // TALEP ALMA AKISI (Firestore transaction)
  // ---------------------------------------------------------------

  Future<void> _onMarkerTapped(WasteRequest request) async {
    if (_tripController.isAnimating) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('🚛 Araç şu an yolda — önce mevcut teslimatı tamamlayın.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final isMine = _activeRequest?.id == request.id;

    final accepted = await showRequestDetailSheet(
      context,
      request: request,
      // Mesafe YAKLASIK konumdan hesaplanir; kartta da "≈" ile gosterilir.
      // Talebi almadan once toplayicinin elinde zaten bu veri var.
      distanceKm:
          MapUtils.distanceKm(_collectorPosition, request.approxLocation),
      isAccepted: isMine,
      // Adres detayi SADECE talep bizdeyse gosterilir; o zaman da veriyi
      // sunucudan yetkiyle okuduk demektir.
      detail: isMine ? _activeDetail : null,
    );

    if (accepted != true || !mounted) return;
    Haptics.action(); // "Talebi Al" onay titresimi

    // --- Firestore'da talebi uzerine al (transaction korumali) ---
    try {
      await ref.read(wasteRequestRepositoryProvider).acceptRequest(
            requestId: request.id,
            collectorId: ref.read(currentUserIdProvider),
            // Gercek hesap adi: kullanicinin takip ekraninda gorunur
            collectorName: ref.read(currentUserNameProvider),
            // Rota baslangici olarak ANLIK konumumuzu yaz — kullanicinin
            // takip ekrani rotayi tam bu noktadan cizecek
            collectorLocation: _collectorPosition,
          );
    } on StateError catch (e) {
      // Baska toplayici bizden once almis — pin stream ile zaten dusecek
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${e.message}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    } catch (e) {
      // FirebaseException dahil diger tum hatalar: guvenli string'e cevir
      final message = logAndReadError(e, context: 'acceptRequest');
      if (mounted) {
        // YETKI REDDI ozel olarak ayrilir: bu bir baglanti sorunu DEGIL,
        // hesabin dogrulanmis toplayici olmamasidir. Ham
        // "[permission-denied] Missing or insufficient permissions"
        // mesaji kullaniciya hicbir sey anlatmaz.
        final isNotCollector = message.contains('permission-denied');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isNotCollector
                  ? 'Bu hesap doğrulanmış saha görevlisi değil. Toplayıcı '
                      'yetkisi ATOS operatörü tarafından tanımlanır.'
                  : 'Bağlantı hatası: $message',
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // --- Maske kalkti: TAM adresi simdi okuyabiliriz ---
    // Bu okuma, transaction ile collectorId'yi uzerimize yazdigimiz icin
    // basarili olur. Talebi almasaydik ayni cagri permission-denied alirdi.
    final RequestDetail? detail;
    try {
      detail =
          await ref.read(wasteRequestRepositoryProvider).getDetail(request.id);
    } catch (e) {
      final message = logAndReadError(e, context: 'getDetail');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Adres detayı alınamadı: $message'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    if (detail == null) {
      // Adres detayi yoksa rota cizilemez — sessizce yanlis yere gitmektense
      // durumu acikca soyluyoruz.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu talebin adres detayı bulunamadı.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _activeDetail = detail;
    _startTrip(request, detail.exactLocation);
  }

  /// Bekleyen talepleri LISTE olarak acar (haritada pin avlamaya gerek yok).
  /// Talepler EN YAKINDAN uzaga siralanir — verimli sevkiyat mantigi.
  /// Bir talebe dokununca kamera oraya kayar ve normal detay/al akisi acilir.
  void _showPendingList(List<WasteRequest> pending) {
    Haptics.tap();
    final sorted = [...pending]
      ..sort((a, b) => MapUtils.distanceKm(_collectorPosition, a.approxLocation)
          .compareTo(MapUtils.distanceKm(_collectorPosition, b.approxLocation)));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => PointerInterceptor(
        child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetCtx).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Surukleme cubugu
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.list_alt, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('Bekleyen Talepler',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('en yakından sıralı',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade500)),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: sorted.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (_, i) {
                  final r = sorted[i];
                  final km = MapUtils.distanceKm(_collectorPosition, r.approxLocation);
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold)),
                    ),
                    title: Text(
                      r.wasteTypes.map((t) => '${t.emoji} ${t.label}').join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '~${r.estimatedKg.toStringAsFixed(0)} kg · '
                      '${km.toStringAsFixed(1)} km uzakta',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.primary),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      // Kamerayi talebe kaydir, sonra detay/al akisini ac
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(r.approxLocation, 14),
                      );
                      _onMarkerTapped(r);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// KESINTI KURTARMA — devam eden bir teslimat varsa kaldigi yerden surdurur.
  ///
  /// Neden gerekli: Toplayicinin aktif gorevi eskiden sadece bu ekranin
  /// bellegindeydi. Mobil tarayici sekmeyi attiginda, sekme arka planda
  /// kalip animasyon karesi (rAF) durdugunda ya da internet gittiginde
  /// gorev 'yolda' durumunda ASKIDA kaliyordu: ne toplayici devam
  /// edebiliyor ne kullanici bir sey gorebiliyordu.
  ///
  /// Artik ekran her acildiginda Firestore'daki gercek duruma bakilir.
  /// Rota, aracin SU ANKI konumundan hedefe yeniden kurulur — yani
  /// yolculuk kaldigi yerden devam etmis gibi gorunur.
  Future<void> _resumeIfInterrupted(WasteRequest delivery) async {
    // Zaten bu gorev uzerinde calisiyoruz ya da bir kez surdurduk
    if (_activeRequest?.id == delivery.id) return;
    if (_resumedRequestId == delivery.id) return;
    if (_tripController.isAnimating) return;
    _resumedRequestId = delivery.id;

    // Adres detayi: bu gorev bizim uzerimizde oldugu icin kural izin verir
    final RequestDetail? detail;
    try {
      detail =
          await ref.read(wasteRequestRepositoryProvider).getDetail(delivery.id);
    } catch (e) {
      logAndReadError(e, context: 'kurtarma/getDetail');
      return;
    }
    if (!mounted || detail == null) return;

    // Toplayici en son nerede kaldiysa oradan devam et
    final resumeFrom = delivery.collectorLocation ?? _collectorPosition;
    setState(() {
      _collectorPosition = resumeFrom;
      _collectorBearing = delivery.collectorBearing ?? _collectorBearing;
      _activeDetail = detail;
    });

    _startTrip(delivery, detail.exactLocation, resumed: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('↻ Devam eden teslimatınız kaldığı yerden sürüyor.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Rota cizer, kamerayi odaklar ve arac animasyonunu baslatir.
  ///
  /// [destination] TAM adrestir ve YALNIZCA talep basariyla uzerimize
  /// alindiktan sonra elde edilebilir (korumali detay dokumani). Yani
  /// rota, maskenin sunucuda kalkmasindan sonra cizilir.
  void _startTrip(
    WasteRequest request,
    LatLng destination, {
    bool resumed = false,
  }) {
    final routePoints =
        MapUtils.buildCurvedRoute(_collectorPosition, destination);

    setState(() {
      _activeRequest = request;
      _activeDestination = destination;
      _activeRoutePoints = routePoints;
      _polylines
        ..clear()
        ..add(
          MapUtils.buildRoutePolyline(
            id: 'route-${request.id}',
            points: routePoints,
            color: AppColors.primary,
          ),
        );
    });

    // GUVENLI sigdirma: noktalar cok yakinsa sabit zoom'a duser,
    // dejenere bounds yuzunden olusan "beyaz ekran / sonsuz zoom" olmaz.
    _mapController?.animateCamera(
      MapUtils.fitTwoPoints(_collectorPosition, destination),
    );

    // Kurtarma sirasinda "Görev alındı" demek yaniltici olur; o durumda
    // bilgilendirmeyi cagiran taraf (_resumeIfInterrupted) yapar.
    if (!resumed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚛 Görev alındı! Araç yola çıkıyor...'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _tripController.forward(from: 0);
    });
  }

  // ---------------------------------------------------------------
  // MARKER URETIMI (canli veriden)
  // ---------------------------------------------------------------

  Set<Marker> _buildMarkers(
    List<WasteRequest> pendingRequests,
    MarkerIcons? icons,
  ) {
    final markers = <Marker>{
      // Toplayici araci — ozel mavi navigasyon ikonu (donebilir)
      Marker(
        markerId: const MarkerId('collector'),
        position: _collectorPosition,
        icon: icons?.vehicle ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        flat: true,
        anchor: const Offset(0.5, 0.5),
        rotation: _collectorBearing,
        zIndex: 10,
        infoWindow: const InfoWindow(title: 'Toplama Aracı'),
      ),
    };

    // GIZLILIK: Bekleyen talepler icin PIN CIZILMEZ. Tam adres bu asamada
    // toplayiciya kapali oldugu icin harita da nokta gostermez; onun yerine
    // yaklasik bolgeyi anlatan bir cember cizilir (bkz. _buildCircles).

    // Su an gidilen hedef artik "bekleyen" listesinde degil; tam adresi
    // uzerimize aldigimiz icin ARTIK NOKTA PIN cizebiliriz.
    final active = _activeRequest;
    final destination = _activeDestination;
    if (active != null && destination != null) {
      markers.add(
        Marker(
          markerId: MarkerId(active.id),
          position: destination,
          icon: icons?.completed ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          anchor: const Offset(0.5, 1.0),
          infoWindow: const InfoWindow(title: 'Toplama adresi'),
          onTap: () => _onMarkerTapped(active),
        ),
      );
    }
    return markers;
  }

  /// Bekleyen taleplerin YAKLASIK bolgesini cizen cemberler.
  ///
  /// Yaricap [_maskRadiusMeters], konum izgarasinin (~555 m) yarisindan
  /// buyuk secildi: gercek nokta cemberin icinde OLDUGU garanti, ama
  /// cemberin neresinde oldugu belirsiz. Toplayici "buralarda bir is var"
  /// bilgisini alir, adresi almaz.
  Set<Circle> _buildCircles(List<WasteRequest> pendingRequests) {
    return pendingRequests.map((request) {
      return Circle(
        circleId: CircleId('area-${request.id}'),
        center: request.approxLocation,
        radius: _maskRadiusMeters,
        fillColor: AppColors.primary.withOpacity(0.14),
        strokeColor: AppColors.primary.withOpacity(0.55),
        strokeWidth: 2,
        consumeTapEvents: true,
        onTap: () => _onMarkerTapped(request),
      );
    }).toSet();
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // KESINTI KURTARMA: bu toplayicinin devam eden gorevi var mi?
    // Sayfa yenilendiyse (mobil sekme atildi, arka planda animasyon
    // durdu, internet gitti) gorev burada bulunur ve surdurulur.
    ref.listen(
      activeDeliveryProvider(ref.watch(currentUserIdProvider)),
      (previous, next) {
        final delivery = next.valueOrNull;
        if (delivery != null) _resumeIfInterrupted(delivery);
      },
    );

    // CANLI VERI: Firestore'daki bekleyen talepleri dinle.
    // Yeni talep yazildigi anda bu widget otomatik yeniden cizilir.
    final pendingAsync = ref.watch(pendingRequestsProvider);
    final pendingRequests = pendingAsync.valueOrNull ?? [];
    final isDriving = _tripController.isAnimating;

    // Ozel marker ikonlari hazir mi? Degilse varsayilan pine dusulur.
    final markerIcons = ref.watch(markerIconsProvider).valueOrNull;

    // AKILLI ROTA: yolda degilken ve >=2 bekleyen talep varken, En Yakin
    // Komsu algoritmasiyla en verimli toplama sirasini hesapla. Sonuc hem
    // haritaya neon bir guzergah cizgisi hem de ustteki rozet olarak yansir.
    final OptimizedRoute? optimized =
        (!isDriving && pendingRequests.length >= 2)
            ? RouteOptimizer.nearestNeighbor(_collectorPosition, pendingRequests)
            : null;

    // Haritada gosterilecek tum cizgiler: aktif teslimat rotasi +
    // (varsa) akilli toplama guzergahi
    final polylines = <Polyline>{
      ..._polylines,
      if (optimized != null)
        Polyline(
          polylineId: const PolylineId('optimized-route'),
          points: optimized.pathPoints,
          color: AppColors.neon,
          width: 4,
          patterns: [PatternItem.dot, PatternItem.gap(12)],
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (c) => _mapController = c,
            initialCameraPosition: const CameraPosition(
              target: _collectorStartLocation,
              zoom: 14,
            ),
            markers: _buildMarkers(pendingRequests, markerIcons),
            // Bekleyen talepler nokta yerine YAKLASIK BOLGE cemberi olarak
            // cizilir; cembere dokunmak detay kartini acar.
            circles: _buildCircles(pendingRequests),
            polylines: polylines,
            zoomControlsEnabled: false,
            // Kamera, pinleri TUM ekrana degil ust/alt UI kartlarinin
            // arasinda kalan GERCEK gorunur alana gore ortalar.
            padding: const EdgeInsets.only(top: 130, bottom: 150),
          ),

          // --- Konum yayini kesildi uyarisi ---
          // Sessiz basarisizlik yok: yayin ust uste 2 kez duserse toplayici
          // bunu ekranda gorur. Kullanicinin takip ekraninin neden dondugu
          // tahmin edilmez, YAZAR.
          if (_failedPushes >= 2)
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.of(context).padding.top + 8,
              child: PointerInterceptor(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusCard),
                    boxShadow: AppColors.softShadow,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Canlı konum yayını kesildi ($_failedPushes deneme). '
                          '${_lastPushError ?? ""}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // --- Akilli Rota Optimizasyonu rozeti ---
          // Sadece optimize edilecek birden fazla durak varken gorunur.
          if (optimized != null)
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.of(context).padding.top + 76,
              child: _SmartRouteBadge(route: optimized),
            ),

          // --- Ust bilgi karti: durum + canli talep sayaci ---
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PointerInterceptor(
                child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 14, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                    children: [
                      // Rol secim ekranina don
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: AppColors.textSecondary),
                        tooltip: 'Geri',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Haptics.tap();
                          Navigator.of(context).maybePop();
                        },
                      ),
                      Icon(
                        isDriving ? Icons.navigation : Icons.local_shipping,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isDriving
                              ? 'Teslimat noktasına gidiliyor...'
                              : 'Toplayıcı Paneli (Canlı)',
                          style:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      // Stream durumuna gore rozet: yukleniyor / hata / sayi
                      pendingAsync.when(
                        loading: () => const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        ),
                        error: (_, __) => const Icon(Icons.cloud_off,
                            color: AppColors.error, size: 20),
                        data: (requests) {
                          final has = requests.isNotEmpty;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              // Talep varsa tikla -> sevkiyat listesi acilir
                              onTap: has
                                  ? () => _showPendingList(requests)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: has
                                      ? Colors.orange.shade100
                                      : Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      has
                                          ? '${requests.length} bekleyen talep'
                                          : 'Bekleyen talep yok',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: has
                                            ? Colors.orange.shade900
                                            : Colors.green.shade900,
                                      ),
                                    ),
                                    if (has) ...[
                                      const SizedBox(width: 3),
                                      Icon(Icons.list_alt,
                                          size: 15,
                                          color: Colors.orange.shade900),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  // Oturum ozeti: bu oturumda teslimat yapildiysa goster
                  // (bellekten gelir, ekstra veritabani sorgusu yok)
                  if (_sessionCount > 0)
                    Padding(
                      // sol hizalama: geri butonunun altina degil, metnin altina
                      padding: const EdgeInsets.only(top: 8, left: 12),
                      child: Row(
                        children: [
                          Icon(Icons.recycling,
                              size: 15, color: Colors.green.shade600),
                          const SizedBox(width: 6),
                          Text(
                            'Bugün toplanan: '
                            '${_sessionKg.toStringAsFixed(0)} kg · '
                            '$_sessionCount teslimat',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade800),
                          ),
                        ],
                      ),
                    ),

                  // GUVENILIRLIK KARNESI — oturumdan bagimsiz, kalici.
                  // Isletmelerin verdigi yildizlardan turetilir; toplayici
                  // kendi puanini degistiremez (kural: update/delete kapali).
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: _MyReputationLine(
                      collectorId: ref.watch(currentUserIdProvider),
                    ),
                  ),
                    ],
                  ),
                ),
              ),
              ),
            ),
          ),

          // --- Yolculuk sirasinda alt ilerleme karti ---
          if (isDriving)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_shipping,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Teslimat noktasına gidiliyor '
                              '(~${_activeRequest?.estimatedKg.toStringAsFixed(0) ?? "?"} kg)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Premium ilerleme cubugu (gradyan + isima + parilti)
                      AnimatedBuilder(
                        animation: _tripController,
                        builder: (_, __) =>
                            PremiumProgressBar(value: _tripController.value),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // --- Sag altta: araca odaklan butonu ---
          Positioned(
            right: 16,
            bottom: isDriving ? 120 : 24,
            child: PointerInterceptor(
              child: FloatingActionButton.small(
                heroTag: 'btn_collector_location',
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                onPressed: () {
                  Haptics.tap();
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(_collectorPosition, 15),
                  );
                },
                child: const Icon(Icons.my_location),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// '🧠 Akıllı Rota Optimizasyonu' rozeti.
///
/// Sadece gorsel bir etiket degil: arkasindaki [RouteOptimizer] gercek
/// bir En Yakin Komsu hesabi yapar; rozet o hesabin durak sayisini ve
/// toplam mesafesini gosterir. Hafif bir nabiz (pulse) animasyonuyla
/// dikkat ceker.
class _SmartRouteBadge extends StatefulWidget {
  const _SmartRouteBadge({required this.route});

  final OptimizedRoute route;

  @override
  State<_SmartRouteBadge> createState() => _SmartRouteBadgeState();
}

class _SmartRouteBadgeState extends State<_SmartRouteBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // Nabiz gibi yumusakca buyuyup kuculen sonsuz animasyon
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          // Nabiz atan pusula ikonu (rota/yon vurgusu — "AI" imasi yok)
          ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.15).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: const Text('🧭', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Akıllı Toplama Rotası',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  // Algoritma adi ACIKCA yazilir — abartmadan, dogru terimle
                  'En Yakın Komşu · ${widget.route.stopCount} durak · '
                  '~${widget.route.totalDistanceKm.toStringAsFixed(1)} km',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // "AI" yerine durust etiket: kullanilan yontemin sinifi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.neon.withOpacity(0.22),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Sezgisel',
              style: TextStyle(
                color: AppColors.neon,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toplayicinin KENDI guvenilirlik karnesi (harita ustu bilgi kartinda).
///
/// Oyunlastirmanin toplayici tarafi: gorevli aldigi yildizlari ve
/// "Güvenilir görevli" rozetini gorur. Rozet esigi bilincli olarak iki
/// kosullu (>=5 teslimat ve >=4.5 ortalama): tek bir 5 yildizla rozet
/// dagitmak onu anlamsizlastirirdi.
class _MyReputationLine extends ConsumerWidget {
  const _MyReputationLine({required this.collectorId});

  final String collectorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (collectorId.isEmpty) return const SizedBox.shrink();
    final rep = ref.watch(collectorReputationProvider(collectorId));

    if (rep.isNew) {
      return Row(
        children: [
          Icon(Icons.star_outline_rounded,
              size: 15, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Text(
            'Henüz değerlendirilmediniz',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5A623)),
        const SizedBox(width: 6),
        Text(
          '${rep.displayScore} · ${rep.count} değerlendirme',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (rep.isTrusted) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
            ),
            child: const Text(
              '🛡 Güvenilir görevli',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.successInk,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
