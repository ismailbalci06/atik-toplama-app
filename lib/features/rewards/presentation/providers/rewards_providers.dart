import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';
import '../../../waste_request/presentation/providers/waste_request_providers.dart';
import '../../data/rewards_repository.dart';
import '../../domain/green_points.dart';
import '../../domain/reward_models.dart';

/// Repository'nin tek ornegi (testlerde override edilebilir).
final rewardsRepositoryProvider = Provider<RewardsRepository>(
  (ref) => RewardsRepository(),
);

/// Odul katalogu — Console'dan yonetilir, uygulama sadece okur.
final rewardCatalogProvider =
    StreamProvider.autoDispose<List<Reward>>((ref) {
  return ref.watch(rewardsRepositoryProvider).watchCatalog();
});

/// Kullanicinin kendi odul talepleri.
final userRedemptionsProvider =
    StreamProvider.autoDispose<List<Redemption>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId.isEmpty) return Stream.value(const <Redemption>[]);
  return ref.watch(rewardsRepositoryProvider).watchUserRedemptions(userId);
});

/// PUAN CUZDANI — hicbir alani veritabaninda saklanmaz.
///
/// Kazanilan: onaylanmis (confirmedKg dolu) teslimatlardan hesaplanir.
/// Harcanan : reddedilmemis odul taleplerinin toplami.
/// Ikisi de canli akislardan geldigi icin cuzdan kendiliginden guncellenir:
/// toplayici teslimati onayladigi an bakiye artar.
final pointsWalletProvider = Provider.autoDispose<PointsWallet>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return PointsWallet.compute(
    requests: ref.watch(userRequestsProvider(userId)).valueOrNull ??
        const <WasteRequest>[],
    redemptions:
        ref.watch(userRedemptionsProvider).valueOrNull ?? const <Redemption>[],
  );
});

/// -----------------------------------------------------------------
/// OPERATOR (yonetici) tarafi
/// -----------------------------------------------------------------

/// Oturum acan kullanici OPERATOR mu?
///
/// Yetki `admins/{uid}` dokumaninin varligindan gelir ve o koleksiyona
/// uygulamadan yazilamaz. Bu provider yalnizca ARAYUZU acar/kapatir;
/// gercek koruma Firestore kuralindadir — biri arayuzu zorlasa bile
/// okuma/yazma sunucuda reddedilir.
final isAdminProvider = StreamProvider.autoDispose<bool>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return ref.watch(rewardsRepositoryProvider).watchIsAdmin(uid);
});

/// Onay bekleyen TUM odul talepleri (yalnizca operator okuyabilir).
final pendingRedemptionsProvider =
    StreamProvider.autoDispose<List<Redemption>>((ref) {
  return ref.watch(rewardsRepositoryProvider).watchPendingRedemptions();
});

/// Belirli bir KULLANICININ cuzdani — operator onay verirken bakiyesini
/// gorebilsin diye. Kullanicinin kendi ekraninda gordugu hesabin AYNISI
/// (ikisi de PointsWallet.compute kullanir).
final walletOfUserProvider =
    Provider.autoDispose.family<PointsWallet, String>((ref, userId) {
  final requests = ref.watch(userRequestsProvider(userId)).valueOrNull ??
      const <WasteRequest>[];
  final redemptions = ref
          .watch(redemptionsOfUserProvider(userId))
          .valueOrNull ??
      const <Redemption>[];
  return PointsWallet.compute(requests: requests, redemptions: redemptions);
});

/// Bir kullanicinin odul talepleri (operator gorunumu icin family).
final redemptionsOfUserProvider = StreamProvider.autoDispose
    .family<List<Redemption>, String>((ref, userId) {
  return ref.watch(rewardsRepositoryProvider).watchRedemptionsOf(userId);
});
