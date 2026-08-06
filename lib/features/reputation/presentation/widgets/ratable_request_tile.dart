import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';
import '../../../waste_request/presentation/widgets/request_tile.dart';
import '../providers/reputation_providers.dart';
import 'rating_sheet.dart';

/// Talep karti + PUANLAMA yolu.
///
/// NEDEN VAR — kapatilan kusur: Puanlama formunun tek bir tetikleyicisi
/// vardi (takip ekrani ACIKKEN teslimatin tamamlandigini gormek). Kullanici
/// sayfayi yenilerse, sekmeyi kapatirsa, geri tusuna basarsa ya da teslimat
/// baska bir ekrandayken tamamlanirsa o firsat KALICI OLARAK kayboluyordu:
/// tamamlanmis talep `openTracking` tarafindan acilmiyor ve gecmis kartlari
/// tiklanamiyordu.
///
/// Artik puanlama gecmis listesinden her zaman erisilebilir. Tek geciciyol
/// yerine kalici bir kapi — "aktif talebe donus" duzeltmesiyle ayni ilke.
class RatableRequestTile extends ConsumerWidget {
  const RatableRequestTile({
    super.key,
    required this.request,
    this.onTapActive,
  });

  final WasteRequest request;

  /// Talep hala aktifse tiklaninca ne olacak (canli takibe git)
  final VoidCallback? onTapActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1) Aktif talep -> davranis degismedi: canli takibe gider
    if (request.status.isActive) {
      return RequestTile(request: request, onTap: onTapActive);
    }

    // 2) Puanlanabilir mi? Yalnizca TAMAMLANMIS ve toplayicisi belli olan
    //    teslimatlar. (Iptal edilen talebin puanlanacak bir teslimati yok.)
    final collectorId = request.collectorId;
    if (request.status != RequestStatus.tamamlandi ||
        collectorId == null ||
        collectorId.isEmpty) {
      return RequestTile(request: request);
    }

    // 3) Daha once puanlandi mi? Dokuman ID'si talep ID'si oldugu icin
    //    bu TEK dokuman okumasi.
    final rating = ref.watch(ratingForRequestProvider(request.id)).valueOrNull;

    if (rating != null) {
      // Verilmis puan gosterilir; tekrar puanlama YOK (kural da kapali)
      return RequestTile(
        request: request,
        actionBadge: _GivenRatingBadge(stars: rating.stars),
      );
    }

    // 4) Henuz puanlanmamis -> kalici "Puanla" daveti
    return RequestTile(
      request: request,
      actionBadge: const _RatePromptBadge(),
      onTap: () {
        Haptics.tap();
        showRatingSheet(
          context,
          requestId: request.id,
          collectorId: collectorId,
          collectorName: request.collectorName ?? 'Toplayıcı',
        );
      },
    );
  }
}

/// "Puanla" daveti — dikkat ceksin diye marka yesili
class _RatePromptBadge extends StatelessWidget {
  const _RatePromptBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_outline_rounded, size: 13, color: AppColors.successInk),
          SizedBox(width: 4),
          Text(
            'Puanla',
            style: TextStyle(
              color: AppColors.successInk,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Verilmis puan — nötr, sadece bilgi
class _GivenRatingBadge extends StatelessWidget {
  const _GivenRatingBadge({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.neutralBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF5A623)),
          const SizedBox(width: 4),
          Text(
            '$stars',
            style: const TextStyle(
              color: AppColors.neutralInk,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
