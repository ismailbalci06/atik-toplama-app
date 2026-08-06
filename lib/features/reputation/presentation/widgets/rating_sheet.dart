import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/collector_reputation.dart';
import '../providers/reputation_providers.dart';

/// Teslimat sonrasi acilan PUANLAMA formu.
///
/// Puanlama BILINCLI OLARAK zorunlu degil: "Şimdi değil" ile gecilebilir.
/// Zorunlu puanlama, isini bitirmek isteyen kullanicilara rastgele yildiz
/// bastirir ve karneyi anlamsizlastirir.
Future<bool?> showRatingSheet(
  BuildContext context, {
  required String requestId,
  required String collectorId,
  required String collectorName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    builder: (_) => RatingSheet(
      requestId: requestId,
      collectorId: collectorId,
      collectorName: collectorName,
    ),
  );
}

class RatingSheet extends ConsumerStatefulWidget {
  const RatingSheet({
    super.key,
    required this.requestId,
    required this.collectorId,
    required this.collectorName,
  });

  final String requestId;
  final String collectorId;
  final String collectorName;

  @override
  ConsumerState<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends ConsumerState<RatingSheet> {
  int _stars = 0;
  final _commentController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// Yildiz sayisina gore kisa geri bildirim — secimin karsiligini gosterir
  String get _starLabel {
    switch (_stars) {
      case 1:
        return 'Çok kötü';
      case 2:
        return 'Kötü';
      case 3:
        return 'İdare eder';
      case 4:
        return 'İyi';
      case 5:
        return 'Mükemmel';
      default:
        return 'Yıldıza dokunarak puan verin';
    }
  }

  Future<void> _submit() async {
    if (_stars == 0) return;
    Haptics.action();
    setState(() => _sending = true);

    try {
      await ref.read(reputationRepositoryProvider).rateDelivery(
            Rating(
              requestId: widget.requestId,
              collectorId: widget.collectorId,
              raterId: ref.read(currentUserIdProvider),
              stars: _stars,
              comment: _commentController.text,
              createdAt: DateTime.now(),
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final message = logAndReadError(e, context: 'rateDelivery');
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Puan gönderilemedi: $message'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return PointerInterceptor(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
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

                Text('Teslimatı değerlendirin', style: text.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  '${widget.collectorName} atığınızı teslim aldı. '
                  'Deneyiminiz nasıldı?',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 20),

                // --- Yildizlar ---
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (i) {
                      final value = i + 1;
                      final selected = value <= _stars;
                      return IconButton(
                        onPressed: () {
                          Haptics.tap();
                          setState(() => _stars = value);
                        },
                        iconSize: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        constraints: const BoxConstraints(),
                        tooltip: '$value yıldız',
                        icon: Icon(
                          selected ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: selected
                              ? const Color(0xFFF5A623)
                              : AppColors.border,
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    _starLabel,
                    style: text.bodySmall?.copyWith(
                      fontWeight: _stars == 0 ? FontWeight.w400 : FontWeight.w700,
                      color: _stars == 0
                          ? AppColors.textSecondary
                          : AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                TextField(
                  controller: _commentController,
                  maxLines: 2,
                  maxLength: 300,
                  decoration: InputDecoration(
                    labelText: 'Yorum (opsiyonel)',
                    hintText: 'Örn: Zamanında geldi, çok yardımcı oldu.',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusField),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    // Yildiz secilmeden gonderilemez
                    onPressed: (_stars == 0 || _sending) ? null : _submit,
                    child: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Text('Değerlendirmeyi Gönder'),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('Şimdi değil'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
