import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Premium gorunumlu ilerleme cubugu.
///
/// Standart [LinearProgressIndicator]'in yerine gecer:
/// - Yesil->neon gradyan dolgu + yumusak ISIMA (glow),
/// - Dolgunun uzerinde surekli akan bir PARILTI (shimmer) seridi,
/// - Yuvarlatilmis uclar.
///
/// [value] 0.0-1.0 arasidir. Parilti kendi ic controller'i ile animasyonlu
/// oldugu icin dis taraftan yalnizca guncel ilerlemeyi vermek yeterlidir.
class PremiumProgressBar extends StatefulWidget {
  const PremiumProgressBar({
    super.key,
    required this.value,
    this.height = 8,
  });

  final double value;
  final double height;

  @override
  State<PremiumProgressBar> createState() => _PremiumProgressBarState();
}

class _PremiumProgressBarState extends State<PremiumProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    // Parilti seridini soldan saga surekli suzulen sonsuz animasyon
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height),
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fullWidth = constraints.maxWidth;
            final fillWidth = fullWidth * v;

            return Stack(
              children: [
                // Zemin (bos kisim)
                Container(color: AppColors.primary.withOpacity(0.12)),

                // Gradyan dolgu + isima
                Container(
                  width: fillWidth,
                  decoration: BoxDecoration(
                    gradient: AppColors.energyGradient,
                    borderRadius: BorderRadius.circular(widget.height),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),

                // Akan parilti seridi (yalnizca dolgunun uzerinde gorunur)
                if (fillWidth > 12)
                  AnimatedBuilder(
                    animation: _shimmer,
                    builder: (context, _) {
                      // Parilti, dolgu genisligi boyunca soldan saga suzulur
                      final shimmerX = (_shimmer.value * (fillWidth + 60)) - 60;
                      return Positioned(
                        left: shimmerX,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0),
                                Colors.white.withOpacity(0.55),
                                Colors.white.withOpacity(0),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
