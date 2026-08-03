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
  final requests =
      ref.watch(userRequestsProvider(userId)).valueOrNull ??
          const <WasteRequest>[];
  final redemptions =
      ref.watch(userRedemptionsProvider).valueOrNull ?? const <Redemption>[];

  final completed = requests
      .where((r) => r.status == RequestStatus.tamamlandi)
      .toList();

  final earned = GreenPoints.earned(completed);
  final spent = redemptions
      .where((r) => r.status.holdsPoints)
      .fold<int>(0, (sum, r) => sum + r.costPoints);

  return PointsWallet(
    earned: earned,
    spent: spent,
    // Yalnizca PUAN URETEN teslimatlar sayilir (onayli olanlar)
    confirmedDeliveries:
        completed.where((r) => GreenPoints.forRequest(r) > 0).length,
  );
});
