// ATIK URETEN AKISI — "aktif talebe geri donus" testleri.
//
// Kapatilan delik: kullanici canli takip ekranindan cikinca aktif talebine
// bir daha ulasamiyordu (RequestTile onTap hicbir yerde baglanmamisti).
// Bu testler tiklanabilirligin DOGRU talepte oldugunu garanti eder:
// aktif talep tiklanir, gecmis talep tiklanmaz.
import 'package:atik_toplama_app/core/theme/app_theme.dart';
import 'package:atik_toplama_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:atik_toplama_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:atik_toplama_app/features/waste_request/domain/models/waste_request_model.dart';
import 'package:atik_toplama_app/features/waste_request/presentation/providers/waste_request_providers.dart';
import 'package:atik_toplama_app/features/waste_request/presentation/widgets/request_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

WasteRequest _request(RequestStatus status) => WasteRequest(
      id: 'req-${status.name}',
      userId: 'u1',
      wasteTypes: const [WasteType.plastik],
      estimatedKg: 80,
      approxLocation: const LatLng(41.0, 29.0),
      createdAt: DateTime.now(),
      status: status,
    );

Widget _wrap(Widget child, {List<WasteRequest> requests = const []}) =>
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u1'),
        currentUserNameProvider.overrideWithValue('Test'),
        userRequestsProvider.overrideWith((ref, arg) => Stream.value(requests)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('RequestStatus.isActive', () {
    test('bekliyor/atandi/yolda aktif, tamamlandi/iptal degil', () {
      expect(RequestStatus.bekliyor.isActive, isTrue);
      expect(RequestStatus.atandi.isActive, isTrue);
      expect(RequestStatus.yolda.isActive, isTrue);
      expect(RequestStatus.tamamlandi.isActive, isFalse);
      expect(RequestStatus.iptal.isActive, isFalse);
    });

    test('iptal YALNIZCA bekliyor durumunda mumkun', () {
      expect(RequestStatus.bekliyor.isCancellable, isTrue);
      // Toplayici yola ciktiktan sonra iptal kapali olmali
      expect(RequestStatus.atandi.isCancellable, isFalse);
      expect(RequestStatus.yolda.isCancellable, isFalse);
    });
  });

  testWidgets('Aktif talep tiklanabilir, ok isareti cizilir', (t) async {
    var tapped = 0;
    await t.pumpWidget(_wrap(
      RequestTile(request: _request(RequestStatus.yolda), onTap: () => tapped++),
    ));

    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await t.tap(find.byType(RequestTile));
    expect(tapped, 1);
  });

  testWidgets('Gecmis talepte ok isareti YOK (olmayan aksiyon vaat etme)',
      (t) async {
    await t.pumpWidget(_wrap(
      RequestTile(request: _request(RequestStatus.tamamlandi)),
    ));

    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('Ana Sayfa: aktif talep varsa takibe donus kisayolu cikar',
      (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(_wrap(
      const DashboardScreen(),
      requests: [_request(RequestStatus.yolda)],
    ));
    await t.pump(const Duration(seconds: 2));

    expect(find.textContaining('takibe dön'), findsOneWidget);
    expect(find.text('Şu an aktif talebiniz yok.'), findsNothing);
  });

  testWidgets('Ana Sayfa: aktif talep yoksa kisayol cikmaz', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(_wrap(
      const DashboardScreen(),
      requests: [_request(RequestStatus.tamamlandi)],
    ));
    await t.pump(const Duration(seconds: 2));

    expect(find.textContaining('takibe dön'), findsNothing);
    expect(find.text('Şu an aktif talebiniz yok.'), findsOneWidget);
  });
}
