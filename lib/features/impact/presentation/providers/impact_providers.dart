import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../waste_request/presentation/providers/waste_request_providers.dart';
import '../../domain/impact_stats.dart';

/// CANLI etki ozeti: Firestore'daki tamamlanmis teslimatlar degistikce
/// otomatik yeniden hesaplanir. Etki Panosu bunu dinler; her yeni teslimat
/// sayaclari gercek zamanli yukseltir.
final impactStatsProvider = StreamProvider.autoDispose<ImpactStats>((ref) {
  return ref
      .watch(wasteRequestRepositoryProvider)
      .getCompletedRequests()
      .map(ImpactStats.fromRequests);
});
