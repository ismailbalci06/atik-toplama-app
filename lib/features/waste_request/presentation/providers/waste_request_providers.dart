import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/waste_request_repository.dart';
import '../../domain/models/waste_request_model.dart';

/// -----------------------------------------------------------------
/// FIRESTORE <-> UI KOPRUSU (Riverpod)
/// -----------------------------------------------------------------
/// StreamProvider'lar Firestore snapshot stream'lerini dinler ve
/// AsyncValue (loading / error / data) olarak UI'a sunar.
/// Veritabaninda bir sey degistigi ANDA ilgili widget'lar otomatik
/// yeniden cizilir — manuel yenileme yoktur.

/// Repository'nin tek (singleton) ornegini saglar.
///
/// Testlerde `overrideWithValue(MockRepository())` ile degistirilir —
/// UI kodu hic degismeden sahte veriyle test edilebilir.
final wasteRequestRepositoryProvider = Provider<WasteRequestRepository>(
  (ref) => WasteRequestRepository(),
);

/// TOPLAYICI ekrani: bekleyen taleplerin canli listesi.
///
/// Kullanim (Asama 2'de):
///   final pending = ref.watch(pendingRequestsProvider);
///   pending.when(data: ..., loading: ..., error: ...)
///
/// Kullanici yeni talep olusturdugu an bu stream tetiklenir ve
/// toplayicinin haritasina yeni pin otomatik duser.
final pendingRequestsProvider =
    StreamProvider.autoDispose<List<WasteRequest>>((ref) {
  return ref.watch(wasteRequestRepositoryProvider).getPendingRequests();
});

/// KULLANICI tarafi: tek bir talebin canli durumu (.family: talep ID'si
/// parametre olarak gecilir).
///
/// "Talebim Yolda" gecisinin kalbi: toplayici "Talebi Al" dediginde
/// buradaki status 'bekliyor' -> 'atandi' olur, dinleyen widget aninda
/// haberdar olur ve takip ekranina yonlendirir.
final requestByIdProvider = StreamProvider.autoDispose
    .family<WasteRequest?, String>((ref, requestId) {
  return ref.watch(wasteRequestRepositoryProvider).watchRequest(requestId);
});

/// Bir kullanicinin tum taleplerinin canli listesi (gecmis ekrani icin).
final userRequestsProvider = StreamProvider.autoDispose
    .family<List<WasteRequest>, String>((ref, userId) {
  return ref.watch(wasteRequestRepositoryProvider).getRequestsByUser(userId);
});

/// TOPLAYICININ devam eden teslimati.
///
/// Dayaniklilik icin: sayfa yenilenirse (mobil tarayici sekmeyi atar,
/// arka planda animasyon durur, internet kesilir) toplayici ekrani bu
/// akistan aktif gorevini bulur ve kaldigi yerden surdurur. Gorev artik
/// ekranin bellegine degil Firestore'a bagli.
final activeDeliveryProvider = StreamProvider.autoDispose
    .family<WasteRequest?, String>((ref, collectorId) {
  return ref
      .watch(wasteRequestRepositoryProvider)
      .watchActiveDeliveryOf(collectorId);
});

/// HASSAS DETAY: tam koordinat + kullanici notu.
///
/// Yetkisi olmayan biri dinlerse Firestore permission-denied firlatir ve
/// bu provider ERROR durumuna duser — arayuz de o zaman maskeli halini
/// gosterir. Yani "gosterme karari" kodun degil, SUNUCUNUN.
///
/// Yetki: talebin sahibi veya talebi uzerine almis toplayici.
final requestDetailProvider = StreamProvider.autoDispose
    .family<RequestDetail?, String>((ref, requestId) {
  return ref.watch(wasteRequestRepositoryProvider).watchDetail(requestId);
});
