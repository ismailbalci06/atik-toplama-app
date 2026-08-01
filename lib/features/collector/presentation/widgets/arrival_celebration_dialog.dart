import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';

/// Arac hedefe vardiginda acilan PREMIUM kutlama dialogu.
///
/// - Yesil tik dairesi, arkasinda genisleyen bir isima halkasiyla
///   "elastik" buyume yapar.
/// - Tema paletindeki (neon/yesil/mavi) konfeti; yerciekimi ivmesiyle
///   duser, kendi ekseninde doner, kurdele ve daire olarak karisir.
///   Harici paket YOK — tek CustomPainter, hafif ve bagimliliksiz.
/// [title] ve [subtitle] verilmezse toplayici tarafina uygun varsayilan
/// metinler kullanilir; kullanici tarafi kendi metinleriyle cagirabilir.
Future<void> showArrivalCelebration(
  BuildContext context, {
  required WasteRequest request,
  String? title,
  String? subtitle,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false, // Buton ile kapatilsin (demo kontrolu bizde)
    builder: (_) => ArrivalCelebrationDialog(
      request: request,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class ArrivalCelebrationDialog extends StatefulWidget {
  const ArrivalCelebrationDialog({
    super.key,
    required this.request,
    this.title,
    this.subtitle,
  });

  final WasteRequest request;
  final String? title;
  final String? subtitle;

  @override
  State<ArrivalCelebrationDialog> createState() =>
      _ArrivalCelebrationDialogState();
}

class _ArrivalCelebrationDialogState extends State<ArrivalCelebrationDialog>
    with TickerProviderStateMixin {
  /// Yesil tik + isima halkasinin buyume animasyonu
  late final AnimationController _checkController;

  /// Konfeti dusme animasyonu (tek sefer, 3 sn)
  late final AnimationController _confettiController;

  /// Konfeti parcaciklari — her biri rastgele konum/renk/bicim/hiz tasir
  late final List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();

    // Tik isareti: elasticOut ile "ziplayarak" buyur
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    // Konfeti: 3 saniyede yukaridan asagi tek sefer yagar
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..forward();

    // 70 rastgele konfeti parcacigi (daha yogun, premium his)
    final random = math.Random();
    _particles = List.generate(70, (_) => _ConfettiParticle.random(random));
  }

  @override
  void dispose() {
    _checkController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // --- Kutlama karti ---
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: AppColors.softShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tik + arkasinda genisleyip sonen isima halkasi
                SizedBox(
                  width: 104,
                  height: 104,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Genisleyen isima halkasi
                      AnimatedBuilder(
                        animation: _checkController,
                        builder: (_, __) {
                          final v = Curves.easeOut
                              .transform(_checkController.value);
                          return Container(
                            width: 60 + 44 * v,
                            height: 60 + 44 * v,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.neon.withOpacity(0.20 * (1 - v)),
                            ),
                          );
                        },
                      ),
                      // Elastik buyuyen yesil tik
                      ScaleTransition(
                        scale: CurvedAnimation(
                          parent: _checkController,
                          curve: Curves.elasticOut,
                        ),
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: const BoxDecoration(
                            gradient: AppColors.energyGradient,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.title ?? 'Teslimat Tamamlandı! 🎉',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle ??
                      '~${widget.request.estimatedKg.toStringAsFixed(0)} kg '
                          '${widget.request.wasteTypes.map((t) => t.label).join(", ")} '
                          'geri dönüşüme kazandırıldı.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Haptics.tap();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Harika, devam et'),
                  ),
                ),
              ],
            ),
          ),

          // --- Konfeti katmani (karta ustten binisir, tiklamayi engellemez) ---
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _confettiController,
                builder: (_, __) => CustomPaint(
                  painter: _ConfettiPainter(
                    particles: _particles,
                    progress: _confettiController.value,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Konfeti parcacigi bicimleri
enum _ConfettiShape { ribbon, circle }

/// Tek bir konfeti parcaciginin ozellikleri.
class _ConfettiParticle {
  final double x;         // Yatay baslangic (0-1, genislige oranli)
  final double startY;    // Dikey baslangic (0-1) — hafif dagilmis kalkis
  final double speed;     // Dusme hizi carpani
  final double size;      // Parcacik boyutu (px)
  final double swayPhase; // Saga-sola salinim fazi
  final double spin;      // Donme hizi carpani
  final Color color;
  final _ConfettiShape shape;

  _ConfettiParticle({
    required this.x,
    required this.startY,
    required this.speed,
    required this.size,
    required this.swayPhase,
    required this.spin,
    required this.color,
    required this.shape,
  });

  /// Rastgele ozelliklerle parcacik uretir (tema paletinden renkler).
  factory _ConfettiParticle.random(math.Random random) {
    const palette = [
      AppColors.neon,      // neon yesil
      AppColors.primary,   // canli yesil
      AppColors.secondary, // acik yesil
      Color(0xFF38BDF8),   // gok mavisi (teknoloji vurgusu)
      Color(0xFFFACC15),   // altin sari (kutlama)
    ];
    return _ConfettiParticle(
      x: random.nextDouble(),
      startY: -0.15 - random.nextDouble() * 0.25,
      speed: 0.7 + random.nextDouble() * 0.9,
      size: 6 + random.nextDouble() * 7,
      swayPhase: random.nextDouble() * math.pi * 2,
      spin: 4 + random.nextDouble() * 8,
      color: palette[random.nextInt(palette.length)],
      shape: random.nextBool() ? _ConfettiShape.ribbon : _ConfettiShape.circle,
    );
  }
}

/// Konfeti parcaciklarini canvas'a cizen painter.
///
/// [progress] 0->1 ilerledikce parcaciklar YERCEKIMI IVMESIYLE (progress^2)
/// duser — gercek dusus gibi hizlanir — ve sinus egrisiyle salinir.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.progress});

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (final p in particles) {
      // Yercekimi: dogrusal degil, progress^2 ile hizlanan dusus
      final fall = progress * progress * p.speed * 1.6;
      final y = (p.startY + fall) * size.height;
      if (y < -20 || y > size.height + 20) continue; // Ekran disi: cizme

      // Sinus ile yatay salinim (yaprak gibi susulme)
      final sway = math.sin(progress * 9 + p.swayPhase) * 16;
      final x = p.x * size.width + sway;

      // Sona dogru hafifce sol (fade-out)
      final opacity = (1 - progress * 0.5).clamp(0.0, 1.0);
      paint.color = p.color.withOpacity(opacity);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(progress * p.spin + p.swayPhase);

      switch (p.shape) {
        case _ConfettiShape.ribbon:
          // Ince, uzun kurdele
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset.zero, width: p.size, height: p.size * 0.45),
              const Radius.circular(2),
            ),
            paint,
          );
        case _ConfettiShape.circle:
          canvas.drawCircle(Offset.zero, p.size * 0.32, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
