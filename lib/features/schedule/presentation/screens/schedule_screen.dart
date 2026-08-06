import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/utils/url_opener.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';
import '../../domain/pickup_schedule.dart';
import '../providers/schedule_providers.dart';

/// TOPLAMA TAKVIMI — duzenli plan tanimlama ekrani.
///
/// DURUSTLUK NOTU (juriye de soylenir): Uygulama KAPALIYKEN bildirim
/// gondermek FCM + zamanlanmis Cloud Function ister; o da Blaze plani
/// ister. Bu yuzden hatirlatmayi iki gercek yoldan veriyoruz:
///   1. Uygulama icinde: gun yaklastiginda Ana Sayfa'da serit
///   2. Isletmenin KENDI takviminde: tekrarlayan Google Takvim etkinligi
///      (telefon kapaliyken bile calisir, sifir backend)
/// Kendi bildirim kanalimiz Faz 2.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final schedulesAsync = ref.watch(schedulesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Toplama Takvimi'),
        automaticallyImplyLeading: !embedded,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Plan Ekle'),
      ),
      body: schedulesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Planlar yüklenemedi: ${readableError(e)}',
                textAlign: TextAlign.center),
          ),
        ),
        data: (schedules) {
          if (schedules.isEmpty) return const _EmptySchedules();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 96),
            children: [
              Text('Düzenli toplama planlarınız', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Plan tanımladığınızda gün yaklaştığında hatırlatırız ve '
                'talebi tek dokunuşla hazır açarız.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 14),
              ...schedules.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ScheduleCard(schedule: s),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    Haptics.tap();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ScheduleEditorSheet(),
    );
  }
}

/// Tek bir plan karti
class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.schedule});

  final PickupSchedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final active = schedule.isActive;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? AppColors.successBg : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  '${schedule.dayOfMonth}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: active
                        ? AppColors.primaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(schedule.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(schedule.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall),
                  ],
                ),
              ),
              Switch(
                value: active,
                activeColor: AppColors.primary,
                onChanged: (v) async {
                  Haptics.tap();
                  try {
                    await ref.read(scheduleRepositoryProvider).setActive(
                          scheduleId: schedule.id,
                          isActive: v,
                        );
                  } catch (e) {
                    final m = logAndReadError(e, context: 'setActive');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Güncellenemedi: $m')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.event_available_rounded,
                    size: 15, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    schedule.reminderText(),
                    style: text.bodySmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Haptics.tap();
                    // Hatirlatma isletmenin KENDI takviminden gelir:
                    // uygulama kapaliyken de calisir.
                    openExternalUrl(schedule.googleCalendarUrl());
                  },
                  icon: const Icon(Icons.calendar_month_rounded, size: 16),
                  label: const Text('Takvime ekle'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Yeni plan olusturma formu
class ScheduleEditorSheet extends ConsumerStatefulWidget {
  const ScheduleEditorSheet({super.key});

  @override
  ConsumerState<ScheduleEditorSheet> createState() =>
      _ScheduleEditorSheetState();
}

class _ScheduleEditorSheetState extends ConsumerState<ScheduleEditorSheet> {
  final _labelController = TextEditingController(text: 'Aylık toplama');
  final Set<WasteType> _types = {WasteType.kagit};
  int _dayOfMonth = 3;
  double _estimatedKg = 100;
  bool _saving = false;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen en az bir atık türü seçin.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    Haptics.action();
    setState(() => _saving = true);
    try {
      await ref.read(scheduleRepositoryProvider).addSchedule(
            PickupSchedule(
              id: '',
              userId: ref.read(currentUserIdProvider),
              label: _labelController.text.trim().isEmpty
                  ? 'Aylık toplama'
                  : _labelController.text.trim(),
              dayOfMonth: _dayOfMonth,
              wasteTypes: _types.toList(),
              estimatedKg: _estimatedKg,
              createdAt: DateTime.now(),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      final m = logAndReadError(e, context: 'addSchedule');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan kaydedilemedi: $m'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Düzenli toplama planı', style: text.headlineSmall),
              const SizedBox(height: 4),
              Text('Her ay aynı gün için hatırlatma kuralım.',
                  style: text.bodySmall),
              const SizedBox(height: 18),

              TextField(
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: 'Plan adı',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusField),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Text('Atık türü', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WasteType.values.map((t) {
                  final selected = _types.contains(t);
                  return FilterChip(
                    label: Text('${t.emoji} ${t.label}'),
                    selected: selected,
                    onSelected: (v) => setState(
                        () => v ? _types.add(t) : _types.remove(t)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),

              // --- Ayin gunu ---
              Row(
                children: [
                  Expanded(
                    child: Text('Her ayın kaçında?', style: text.titleSmall),
                  ),
                  Text(
                    '$_dayOfMonth',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _dayOfMonth.toDouble(),
                min: 1,
                // 28 UST SINIR: 29/30/31'de "olmayan gun" sorunu cikar.
                max: PickupSchedule.maxDayOfMonth.toDouble(),
                divisions: PickupSchedule.maxDayOfMonth - 1,
                label: '$_dayOfMonth',
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _dayOfMonth = v.round()),
              ),
              Text(
                'Her ay güvenle tekrar edebilmesi için en fazla 28 seçilebilir '
                '(şubatta kayma olmasın).',
                style: text.bodySmall,
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: Text('Tahmini miktar', style: text.titleSmall),
                  ),
                  Text(
                    '~${_estimatedKg.toStringAsFixed(0)} kg',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _estimatedKg,
                min: 5,
                max: 250,
                divisions: 49,
                label: '${_estimatedKg.toStringAsFixed(0)} kg',
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _estimatedKg = v),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Text('Planı Kaydet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hic plan yokken
class _EmptySchedules extends StatelessWidget {
  const _EmptySchedules();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: AppColors.successBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event_repeat_rounded,
                  size: 30, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 14),
            Text('Henüz planınız yok',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Deponuz her ay aynı dönemde doluyorsa bir plan tanımlayın; '
              'gün yaklaştığında hatırlatalım.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
