import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/models/waste_request_model.dart';

/// Tek talep satiri — tasarimdaki "Son Talepler" duzeni.
///
/// Hem Ana Sayfa (son 3 talep) hem Talepler ekrani ayni bileseni kullanir;
/// boylece iki yerde gorunum birebir ayni kalir.
class RequestTile extends StatelessWidget {
  const RequestTile({
    super.key,
    required this.request,
    this.onTap,
    this.actionBadge,
  });

  final WasteRequest request;
  final VoidCallback? onTap;

  /// Durum rozetinden ONCE cizilen ek rozet (ornegin "Puanla" daveti ya da
  /// verilmis yildiz). Bos birakilirsa hicbir sey cizilmez.
  final Widget? actionBadge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.softShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              // Yuvarlak acik yesil ikon kutusu
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.recycling,
                    color: AppColors.primaryDark, size: 21),
              ),
              const SizedBox(width: 12),

              // Baslik + "#id · kg · tarih"
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      request.wasteTypes.map((t) => t.label).join(' + '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '#$_shortId · ${request.estimatedKg.toStringAsFixed(0)} kg'
                      ' · ${_shortDate(request.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              if (actionBadge != null) ...[
                actionBadge!,
                const SizedBox(width: 6),
              ],
              badgeFor(request.status),
              // Ok isareti YALNIZCA gercekten tiklanabilirken cizilir;
              // aksi halde kullaniciya olmayan bir aksiyon vaat ediyorduk.
              if (onTap != null)
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary, size: 20)
              else
                const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Dokuman ID'sinin kisa gosterimi
  String get _shortId {
    final id = request.id;
    return id.length <= 4 ? id : id.substring(0, 4).toUpperCase();
  }

  /// Durum -> tasarimdaki rozet varyanti
  static Widget badgeFor(RequestStatus s) {
    switch (s) {
      case RequestStatus.bekliyor:
        return StatusBadge.neutral('Bekliyor');
      case RequestStatus.atandi:
      case RequestStatus.yolda:
        return StatusBadge.warning('Yolda');
      case RequestStatus.tamamlandi:
        return StatusBadge.success('Tamamlandı');
      case RequestStatus.iptal:
        return StatusBadge.danger('İptal');
    }
  }

  /// Tasarimdaki kisa tarih bicimi: "28 Tem"
  static String _shortDate(DateTime d) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
