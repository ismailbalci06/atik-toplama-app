import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/app_colors.dart';

/// Haritada kullanilan OZEL isaretci (marker) ikon paketi.
///
/// NEDEN CANVAS ILE URETIYORUZ (PNG asset yerine)?
/// - Flutter Web'de `defaultMarkerWithHue` renk (hue) destegi guvenilir
///   degil; tum pinler kirmizi gorunebiliyor. `fromAssetImage` ise web'de
///   ekstra ImageConfiguration/asset pipeline gerektiriyor.
/// - Bunun yerine ikonlari CALISMA ANINDA Canvas'a cizip PNG bayta cevirip
///   [BitmapDescriptor.fromBytes] ile veriyoruz: asset dosyasi YOK, her
///   ekran yogunlugunda (DPR) keskin, renkleri tek yerden yonetilebilir ve
///   Web + mobil hepsinde ayni gorunur.
class MarkerIcons {
  const MarkerIcons({
    required this.pending,
    required this.completed,
    required this.home,
    required this.vehicle,
  });

  /// Bekleyen talep — turuncu damla pin + geri donusum ikonu
  final BitmapDescriptor pending;

  /// Alinan/tamamlanan talep — yesil damla pin + onay ikonu
  final BitmapDescriptor completed;

  /// Kullanicinin adresi — yesil damla pin + ev ikonu
  final BitmapDescriptor home;

  /// Toplayici araci — mavi daire + donebilen navigasyon oku
  final BitmapDescriptor vehicle;

  /// Tum ikonlari bir kez uretir. Riverpod [markerIconsProvider] uzerinden
  /// cagrilir; hazir olana kadar ekranlar varsayilan pine duser.
  static Future<MarkerIcons> build() async {
    final results = await Future.wait([
      _pin(AppColors.primary.withOpacity(1), Icons.recycling,
          fill: const Color(0xFFF59E0B)), // turuncu bekleyen
      _pin(const Color(0xFF16A34A), Icons.check_rounded), // yesil tamamlanan
      _pin(const Color(0xFF16A34A), Icons.home_rounded), // yesil ev
      _circle(const Color(0xFF2563EB), Icons.navigation_rounded), // mavi arac
    ]);
    return MarkerIcons(
      pending: results[0],
      completed: results[1],
      home: results[2],
      vehicle: results[3],
    );
  }

  /// Damla (teardrop) pin cizer: renkli govde + beyaz halka + beyaz ikon.
  /// Ucu altta ortalanmistir; bu yuzden marker anchor'i (0.5, 1.0) olmali.
  static Future<BitmapDescriptor> _pin(
    Color color,
    IconData icon, {
    Color? fill,
  }) async {
    const double w = 46, h = 60, scale = 3;
    final body = fill ?? color;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);

    final headCenter = const Offset(w / 2, w / 2 - 1);
    const radius = 17.0;

    // Yumusak golge (ucun altinda)
    canvas.drawOval(
      Rect.fromCenter(
          center: const Offset(w / 2, h - 4), width: 20, height: 7),
      Paint()
        ..color = Colors.black.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Pin govdesi: daire + asagi ucgen kuyruk
    final path = Path()
      ..addOval(Rect.fromCircle(center: headCenter, radius: radius))
      ..moveTo(w / 2 - 8, headCenter.dy + 12)
      ..lineTo(w / 2, h - 2)
      ..lineTo(w / 2 + 8, headCenter.dy + 12)
      ..close();
    canvas.drawPath(path, Paint()..color = body..isAntiAlias = true);

    // Beyaz halka
    canvas.drawCircle(
      headCenter,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..isAntiAlias = true,
    );

    _drawGlyph(canvas, icon, headCenter, 20, Colors.white);

    return _toDescriptor(recorder, w, h, scale);
  }

  /// Daire isaretci: renkli daire + beyaz ikon. Donebilir (arac) — anchor
  /// (0.5, 0.5) ve marker.rotation ile yon gosterir.
  static Future<BitmapDescriptor> _circle(Color color, IconData icon) async {
    const double d = 42, scale = 3;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);

    final center = const Offset(d / 2, d / 2);
    const radius = d / 2 - 3;

    canvas.drawCircle(
      center + const Offset(0, 1),
      radius,
      Paint()
        ..color = Colors.black.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, radius, Paint()..color = color..isAntiAlias = true);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..isAntiAlias = true,
    );
    _drawGlyph(canvas, icon, center, 20, Colors.white);

    return _toDescriptor(recorder, d, d, scale);
  }

  /// Bir Material ikon glifini canvas'a ortalayarak cizer.
  static void _drawGlyph(
    Canvas canvas,
    IconData icon,
    Offset center,
    double fontSize,
    Color color,
  ) {
    final tp = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      )
      ..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// Cizilen resmi PNG bayta cevirip BitmapDescriptor uretir.
  /// [size] yalnizca Web'de goruntuleme boyutunu (logical px) belirler.
  static Future<BitmapDescriptor> _toDescriptor(
    ui.PictureRecorder recorder,
    double w,
    double h,
    double scale,
  ) async {
    final image = await recorder
        .endRecording()
        .toImage((w * scale).round(), (h * scale).round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    // ignore: deprecated_member_use
    return BitmapDescriptor.fromBytes(
      data!.buffer.asUint8List(),
      size: Size(w, h),
    );
  }
}

/// Ozel marker ikonlarini bir kez uretip paylasan provider.
/// Hazir olana kadar `valueOrNull` null doner; ekranlar o sirada
/// varsayilan pine duser (asla cokme yok).
final markerIconsProvider =
    FutureProvider<MarkerIcons>((ref) => MarkerIcons.build());
