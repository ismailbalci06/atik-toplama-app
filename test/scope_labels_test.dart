// KAPSAM ETIKETLERI TESTI.
//
// Neden: sayaclarin hangi kapsama ait oldugu (SISTEM GENELI vs KISISEL)
// ekranda yazili olmazsa, rakamlarin tutmamasi bir sayac hatasi gibi
// gorunuyor. Bu test etiketlerin gercekten cizildigini ve dar telefon
// genisliginde (360px) tasma yapmadigini garanti eder.
//
// NOT: widget testlerinde sabit genislikli test fontu kullanilir; metinler
// tarayicidakinden GENIS cizilir. Yani burada tasma yoksa gercek tarayicida
// da yoktur (tersi her zaman dogru degil).
import 'package:atik_toplama_app/core/theme/app_theme.dart';
import 'package:atik_toplama_app/core/widgets/impact_dashboard.dart';
import 'package:atik_toplama_app/core/widgets/scope_badge.dart';
import 'package:atik_toplama_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:atik_toplama_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:atik_toplama_app/features/reports/presentation/screens/reports_screen.dart';
import 'package:atik_toplama_app/features/waste_request/domain/models/waste_request_model.dart';
import 'package:atik_toplama_app/features/waste_request/presentation/providers/waste_request_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  final sample = [
    WasteRequest(
      id: 'r1',
      userId: 'u1',
      wasteTypes: const [WasteType.plastik, WasteType.kagit],
      estimatedKg: 120,
      approxLocation: const LatLng(41.0, 29.0),
      createdAt: DateTime.now(),
      status: RequestStatus.tamamlandi,
    ),
  ];

  Widget wrap(Widget child) => ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('u1'),
          currentUserNameProvider.overrideWithValue('Test'),
          userRequestsProvider.overrideWith((ref, arg) => Stream.value(sample)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: child),
        ),
      );

  testWidgets('Rol Secim panosu: sistem geneli kapsami yaziyor', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(wrap(
      SingleChildScrollView(
        child: ImpactDashboard(
          deliveries: 12,
          wasteRecycledKg: 840,
          co2PreventedKg: 1300,
          treesSaved: 3.4,
          scopeBadge: ScopeBadge.global(),
          scopeNote: 'Tüm ATOS kullanıcılarının tamamlanan teslimatları',
        ),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('Çevresel Etkimiz'), findsOneWidget);
    expect(find.text('Sistem geneli'), findsOneWidget);
    expect(
      find.text('Tüm ATOS kullanıcılarının tamamlanan teslimatları'),
      findsOneWidget,
    );
  });

  testWidgets('Ana Sayfa: kisisel kapsam basligi ve rozeti var', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(wrap(const DashboardScreen()));
    await t.pump(const Duration(seconds: 2));

    expect(find.text('Tesisinizin Çevresel Etkisi'), findsOneWidget);
    expect(find.text('Size özel'), findsOneWidget);
    expect(find.text('Yalnızca sizin taleplerinizden hesaplanır'),
        findsOneWidget);
  });

  testWidgets('Rapor: kisisel kapsam rozeti ve bolum basligi var', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(wrap(const ReportsScreen()));
    await t.pump(const Duration(seconds: 2));

    expect(find.text('Size özel'), findsOneWidget);
    expect(find.text('Tesisinizin Çevresel Etkisi'), findsOneWidget);
    expect(find.text('Tamamlanan kendi teslimatlarınız'), findsOneWidget);
  });
}
