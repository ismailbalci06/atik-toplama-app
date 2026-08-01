import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';

/// Pin'e tiklandiginda acilan "Talep Detayi" karti.
///
/// [showRequestDetailSheet] ile acilir. Toplayici "Talebi Al & Rotayı Çiz"
/// butonuna basarsa true, karti oylece kapatirsa null doner.
Future<bool?> showRequestDetailSheet(
  BuildContext context, {
  required WasteRequest request,
  required double distanceKm, // Toplayicinin talebe kus ucusu uzakligi
  required bool isAccepted,   // Bu talep daha once alinmis mi?
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    // Kartin asagidan yukari yumusak bir animasyonla gelmesi icin
    transitionAnimationController: null, // varsayilan slide-up animasyonu
    builder: (_) => RequestDetailSheet(
      request: request,
      distanceKm: distanceKm,
      isAccepted: isAccepted,
    ),
  );
}

class RequestDetailSheet extends StatelessWidget {
  const RequestDetailSheet({
    super.key,
    required this.request,
    required this.distanceKm,
    required this.isAccepted,
  });

  final WasteRequest request;
  final double distanceKm;
  final bool isAccepted;

  /// Talebin ne kadar once olusturuldugunu insan diliyle yazar.
  /// Orn: "25 dk önce", "2 sa önce"
  String get _timeAgo {
    final diff = DateTime.now().difference(request.createdAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    return '${diff.inHours} sa önce';
  }

  @override
  Widget build(BuildContext context) {
    // Tiklamalarin arkadaki haritaya sizmasini engelle (bkz. Web notu)
    return PointerInterceptor(
      child: Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Surukleme cubugu ---
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // --- Baslik satiri: talep no + zaman etiketi ---
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  // Liste satirlariyla AYNI kisa kimlik bicimi (#ABCD)
                  'Talep #${request.id.length <= 4 ? request.id : request.id.substring(0, 4).toUpperCase()}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.schedule, size: 15, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                _timeAgo,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- Atik turleri (chip listesi) ---
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: request.wasteTypes
                .map(
                  (type) => Chip(
                    label: Text('${type.emoji} ${type.label}'),
                    backgroundColor: AppColors.secondary.withOpacity(0.15),
                    side: BorderSide.none,
                    labelStyle: const TextStyle(fontSize: 13),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),

          // --- Miktar ve mesafe bilgi kutulari ---
          Row(
            children: [
              _InfoBox(
                icon: Icons.scale,
                label: 'Tahmini Miktar',
                value: '~${request.estimatedKg.toStringAsFixed(0)} kg',
              ),
              const SizedBox(width: 12),
              _InfoBox(
                icon: Icons.near_me,
                label: 'Uzaklık',
                value: '${NumberFormat("0.0").format(distanceKm)} km',
              ),
            ],
          ),

          // --- Kullanici notu (varsa goster) ---
          if (request.note != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 18, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request.note!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // --- Ana aksiyon butonu ---
          SizedBox(
            width: double.infinity,
            height: 52,
            child: isAccepted
                // Talep tamamlanmissa pasif gorunum
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Teslimat tamamlandı ✅'),
                  )
                // Alinmamissa dikkat cekici "Talebi Al" butonu
                : ElevatedButton.icon(
                    onPressed: () {
                      Haptics.action(); // Onemli aksiyon: dokunsal geri bildirim
                      // true dondurerek harita ekranina "talep alindi"
                      // sinyali gonder; rota cizimi orada yapilacak
                      Navigator.of(context).pop(true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.route),
                    label: const Text(
                      'Talebi Al & Rotayı Çiz',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Miktar / mesafe gibi kucuk bilgi kutulari icin tekrar kullanilabilir widget.
class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
