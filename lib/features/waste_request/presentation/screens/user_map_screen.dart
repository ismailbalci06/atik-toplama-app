import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_utils.dart';
import '../../domain/models/waste_request_model.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/location_provider.dart';
import '../providers/waste_request_providers.dart';
import '../widgets/waste_request_bottom_sheet.dart';
import 'request_history_screen.dart';
import 'request_tracking_screen.dart';

/// Kullanici (Atik Veren) tarafinin ana harita ekrani.
///
/// - Google Maps uzerinde kullanicinin mevcut konumunu gosterir.
/// - Alt sagdaki buton ile "Atik Talebi Olustur" bottom sheet'i acilir.
/// - Kullanicinin AKTIF talepleri haritada yesil pin olarak durur.
///   Pin'ler yerel state'ten DEGIL, Firestore'dan gelir: ekrandan cikip
///   dondugunde de, baska bir cihazdan bakildiginda da ayni pin'ler
///   gorunur; talep tamamlaninca/iptal edilince kendiliginden kaybolur.
///   Pin'e dokunmak canli takip ekranini acar.
class UserMapScreen extends ConsumerStatefulWidget {
  const UserMapScreen({super.key});

  @override
  ConsumerState<UserMapScreen> createState() => _UserMapScreenState();
}

class _UserMapScreenState extends ConsumerState<UserMapScreen> {
  /// Harita controller'i — kamera hareketleri icin kullanilir
  GoogleMapController? _mapController;

  /// Harita olusturuldugunda controller'i sakla
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  /// Kullanicinin AKTIF taleplerinden harita pin'lerini uretir.
  /// Kaynak Firestore oldugu icin liste her degistiginde pin'ler
  /// kendiliginden guncellenir (elle ekleme/silme yok).
  Set<Marker> _buildMarkers(List<WasteRequest> requests) {
    return requests.where((r) => r.status.isActive).map((r) {
      final types = r.wasteTypes.map((t) => t.label).join(', ');
      return Marker(
        markerId: MarkerId(r.id),
        // Kendi ekranimiz ama yine de acik dokumandaki yaklasik konumu
        // kullaniyoruz: tam koordinat icin ekstra bir korumali okuma
        // gerekirdi ve kullanici zaten kendi adresini biliyor.
        position: r.approxLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Toplama Talebi',
          snippet: '$types • ~${r.estimatedKg.toStringAsFixed(0)} kg',
          // Balona dokununca canli takibe don
          onTap: () => openTracking(context, r),
        ),
      );
    }).toSet();
  }

  /// "Talep Olustur" akisini baslatir:
  /// 1) Bottom sheet'i acar ve kullanicinin formu doldurmasini bekler
  /// 2) Form onaylanirsa talebi FIRESTORE'A YAZAR (addRequest)
  /// 3) Donen dokuman ID'siyle canli takip ekranina gecer — orasi
  ///    talebin durumunu Firestore'dan dinler; toplayici talebi alinca
  ///    ekran otomatik "yolda" animasyonuna gecer
  Future<void> _openRequestSheet(LatLng userLocation) async {
    final input = await showWasteRequestSheet(
      context,
      location: userLocation,
    );

    // Kullanici sheet'i kapattiysa (iptal) hicbir sey yapma
    if (input == null || !mounted) return;

    final userId = ref.read(currentUserIdProvider);

    // --- Talebi Firestore'a yaz ---
    // Repository iki dokuman yazar: acik ozet + korumali adres detayi.
    // Tam koordinatin acik dokumana sizmasi burada degil, repository'de
    // (ve Firestore kuralinda) engellenir.
    final String docId;
    try {
      docId = await ref.read(wasteRequestRepositoryProvider).addRequest(
            input: input,
            userId: userId,
          );
    } catch (e) {
      // GUVENLI yakalama: hatayi ham nesne olarak degil, readableError ile
      // string'e cevirerek kullan (Flutter Web tip cokmesini onler + asil
      // Firebase hatasini konsola basar)
      final message = logAndReadError(e, context: 'addRequest');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Talep oluşturulamadı: $message'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    // Takip ekrani dokumani ID ile dinleyecegi icin, talebi
    // Firestore'un verdigi GERCEK ID ile yeniden olusturuyoruz.
    // Tam koordinati buraya koymuyoruz: takip ekrani onu korumali detay
    // dokumanindan (sahibi oldugu icin yetkili) kendisi okur.
    final request = WasteRequest(
      id: docId,
      userId: userId,
      wasteTypes: input.wasteTypes,
      estimatedKg: input.estimatedKg,
      approxLocation: snapToPrivacyGrid(input.exactLocation),
      createdAt: DateTime.now(),
    );

    // NOT: Pin'i burada ELLE eklemiyoruz — talep Firestore'a yazildigi anda
    // userRequestsProvider akisi yeni listeyi yayinlar ve pin kendiliginden
    // haritaya duser (tek gercek kaynak Firestore).

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Talebiniz oluşturuldu!'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );

    // Canli takip ekranina gec — "toplayici araniyor" durumu artik
    // sahte gecikme degil: Firestore'daki status degisimini bekliyor
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestTrackingScreen(request: request),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod uzerinden kullanicinin konumunu izle.
    // AsyncValue sayesinde yukleme / hata / veri durumlarini ayri ayri cizeriz.
    final locationAsync = ref.watch(userLocationProvider);

    // Kullanicinin kendi talepleri — haritadaki pin'lerin CANLI kaynagi.
    // Repository kurali korunuyor: UI Firestore'a dogrudan dokunmuyor,
    // provider uzerinden okuyor.
    final myRequests = ref
            .watch(userRequestsProvider(ref.watch(currentUserIdProvider)))
            .valueOrNull ??
        const <WasteRequest>[];

    return Scaffold(
      body: locationAsync.when(
        // --- Konum aliniyor: yukleme gostergesi ---
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text('Konumunuz alınıyor...'),
            ],
          ),
        ),

        // --- Konum alinamadi: hata mesaji + fallback secenegi ---
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_off,
                    size: 56, color: AppColors.error),
                const SizedBox(height: 12),
                Text(
                  err.toString().replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Kullanici izni verdikten sonra tekrar denemek icin
                ElevatedButton(
                  onPressed: () => ref.invalidate(userLocationProvider),
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),

        // --- Konum alindi: haritayi ciz ---
        data: (userLocation) => Stack(
          children: [
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: userLocation,
                zoom: 15,
              ),
              markers: _buildMarkers(myRequests),
              myLocationEnabled: true,        // Mavi "ben buradayim" noktasi
              myLocationButtonEnabled: false, // Kendi butonumuzu kullanacagiz
              zoomControlsEnabled: false,     // Varsayilan zoom butonlarini gizle
              // Diger ekranlarla tutarli cerceveleme (ust kart / alt buton)
              padding: const EdgeInsets.only(top: 110, bottom: 120),
            ),

            // --- Ust kisimdaki bilgi karti ---
            // PointerInterceptor: tiklamalar arkadaki haritaya sizmasin
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
                    padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
                    child: Row(
                      children: [
                        // Rol secim ekranina don (mobilde tarayici geri
                        // tusuna bagimli kalmamak icin uygulama ici cikis)
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
                        const Icon(Icons.recycling, color: AppColors.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Toplu atığınızı merkezinizden alalım 🌱',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        // Taleplerim: gecmisin GERCEK Firestore verisinden
                        IconButton(
                          icon: const Icon(Icons.receipt_long,
                              color: AppColors.primary),
                          tooltip: 'Taleplerim',
                          onPressed: () {
                            Haptics.tap();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RequestHistoryScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                ),
              ),
            ),

            // --- Sag altta konumuma don butonu ---
            Positioned(
              right: 16,
              bottom: 100,
              child: PointerInterceptor(
                child: FloatingActionButton.small(
                heroTag: 'btn_my_location',
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                onPressed: () {
                  // Kamerayi kullanicinin konumuna geri getir
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(userLocation, 15),
                  );
                },
                child: const Icon(Icons.my_location),
              ),
              ),
            ),

            // --- Alt kisimda ana aksiyon butonu: Talep Olustur ---
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: PointerInterceptor(
                child: SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => _openRequestSheet(userLocation),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text(
                    'Atık Talebi Oluştur',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
