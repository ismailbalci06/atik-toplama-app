// SSS sayfasi — hizalama regresyon testi.
//
// Bulunan pürüz: KISA cevaplar ekranin ortasina hizalaniyordu, uzunlar
// sola yasliydi. Sebep ExpansionTile'in ince bir davranisi:
// cocuklari once bir Column'a, o Column'u da bir Align'a sarar.
// `expandedCrossAxisAlignment` yalnizca Column'un IC hizasini belirler;
// disaridaki Align'in varsayilani Alignment.center'dir. Uzun metin tum
// genisligi kapladigi icin fark edilmez, kisa metin ortalanir.
//
// Bu test iki ayarin da yerinde kaldigini garanti eder.
import 'package:atik_toplama_app/core/theme/app_theme.dart';
import 'package:atik_toplama_app/features/faq/presentation/screens/faq_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host() => MaterialApp(
        theme: AppTheme.light,
        home: const FaqScreen(),
      );

  testWidgets('cevaplar SOLA yasli — kisa metin ortalanmaz', (t) async {
    t.view.physicalSize = const Size(420, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(host());
    await t.pump();

    final tiles = t.widgetList<ExpansionTile>(find.byType(ExpansionTile));
    expect(tiles, isNotEmpty, reason: 'SSS soru listesi bos olmamali');

    for (final tile in tiles) {
      expect(tile.expandedAlignment, Alignment.centerLeft,
          reason: 'disaridaki Align sola yasli olmali (varsayilani center)');
      expect(tile.expandedCrossAxisAlignment, CrossAxisAlignment.start,
          reason: 'Column ic hizasi da sola yasli olmali');
    }
  });

  testWidgets('sayfa durumsuz ve tum kategoriler ciziliyor', (t) async {
    t.view.physicalSize = const Size(420, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(host());
    await t.pump();

    // Durumsuz olmasi kod dondurma doneminde eklenebilmesinin gerekcesiydi
    expect(find.byType(FaqScreen), findsOneWidget);
    expect(t.widget<FaqScreen>(find.byType(FaqScreen)), isA<StatelessWidget>());

    // Alti kategori basligi
    expect(find.text('Genel Kullanım ve İşleyiş'), findsOneWidget);
    expect(find.text('Roller, Yetkilendirme ve Güvenlik'), findsOneWidget);
    expect(find.text('Gizlilik ve Kişisel Veri'), findsOneWidget);
  });

  testWidgets('kisa cevapli soru acildiginda metin gorunur', (t) async {
    t.view.physicalSize = const Size(420, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(host());
    await t.pump();

    // Sikayete konu olan kisa cevaplardan biri
    final soru = find.text('Uygulamayı kullanmak ücretli mi?');
    expect(soru, findsOneWidget);

    await t.tap(soru);
    await t.pumpAndSettle();

    expect(find.textContaining('ücretsiz sunulur'), findsOneWidget);
  });
}
