import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reputation_repository.dart';
import '../../domain/collector_reputation.dart';

/// Repository'nin tek ornegi (testlerde override edilebilir).
final reputationRepositoryProvider = Provider<ReputationRepository>(
  (ref) => ReputationRepository(),
);

/// Bir toplayicinin canli puan listesi.
final collectorRatingsProvider = StreamProvider.autoDispose
    .family<List<Rating>, String>((ref, collectorId) {
  return ref.watch(reputationRepositoryProvider).watchRatingsOf(collectorId);
});

/// Bir toplayicinin GUVENILIRLIK KARNESI.
///
/// Ortalama saklanmaz, burada turetilir — Yesil Puan bakiyesiyle ayni
/// felsefe. Veri henuz gelmediyse "yeni gorevli" (bos karne) donulur;
/// boylece arayuz hicbir zaman bos/hatali bir puan gostermez.
final collectorReputationProvider = Provider.autoDispose
    .family<CollectorReputation, String>((ref, collectorId) {
  final ratings =
      ref.watch(collectorRatingsProvider(collectorId)).valueOrNull ??
          const <Rating>[];
  return CollectorReputation.compute(ratings);
});

/// Belirli bir teslimatin puani (verilmemisse null).
/// "Puanla" davetini gostermek/gizlemek icin kullanilir.
final ratingForRequestProvider =
    StreamProvider.autoDispose.family<Rating?, String>((ref, requestId) {
  return ref.watch(reputationRepositoryProvider).watchRatingFor(requestId);
});
