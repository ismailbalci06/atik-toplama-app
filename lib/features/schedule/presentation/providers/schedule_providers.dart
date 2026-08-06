import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/schedule_repository.dart';
import '../../domain/pickup_schedule.dart';

final scheduleRepositoryProvider = Provider<ScheduleRepository>(
  (ref) => ScheduleRepository(),
);

/// Oturum acan kullanicinin TUM planlari (pasifler dahil).
final schedulesProvider =
    StreamProvider.autoDispose<List<PickupSchedule>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return ref.watch(scheduleRepositoryProvider).watchSchedulesOf(userId);
});

/// Ana Sayfa seridinde gosterilecek plan — YAKLASAN ve AKTIF olan.
///
/// Turetilmis deger: hicbir yerde "sonraki hatirlatma" saklanmaz, her
/// seferinde plandan hesaplanir. Birden fazla plan yaklasiyorsa en yakini
/// secilir; hicbiri yaklasmadiysa null doner ve serit hic cizilmez.
final upcomingScheduleProvider = Provider.autoDispose<PickupSchedule?>((ref) {
  final schedules = ref.watch(schedulesProvider).valueOrNull ??
      const <PickupSchedule>[];

  final due = schedules.where((s) => s.isActive && s.isDueSoon()).toList()
    ..sort((a, b) => a.daysUntil().compareTo(b.daysUntil()));

  return due.isEmpty ? null : due.first;
});
