// GUVENILIRLIK PUANI (Modul A) — karne hesabi ve puanlama formu testleri.
//
// Mimari ilke: ortalama puan HICBIR YERDE SAKLANMAZ, ham puanlardan
// turetilir (Yesil Puan bakiyesiyle ayni felsefe). Bu testler o turetmenin
// dogrulugunu ve "olmayan puani uydurmama" davranisini garanti eder.
import 'package:atik_toplama_app/core/theme/app_theme.dart';
import 'package:atik_toplama_app/features/reputation/domain/collector_reputation.dart';
import 'package:atik_toplama_app/features/reputation/presentation/widgets/rating_sheet.dart';
import 'package:atik_toplama_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:atik_toplama_app/features/reputation/presentation/providers/reputation_providers.dart';
import 'package:atik_toplama_app/features/reputation/presentation/widgets/ratable_request_tile.dart';
import 'package:atik_toplama_app/features/waste_request/domain/models/waste_request_model.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Rating _rating(int stars) => Rating(
      requestId: 'r$stars',
      collectorId: 'c1',
      raterId: 'u1',
      stars: stars,
      createdAt: DateTime.now(),
    );

void main() {
  _regression();

  group('CollectorReputation.compute', () {
    test('puan yoksa YENI GOREVLI — uydurma puan gosterilmez', () {
      final rep = CollectorReputation.compute(const []);
      expect(rep.isNew, isTrue);
      expect(rep.count, 0);
      expect(rep.displayScore, '—');
      expect(rep.label, 'Yeni görevli');
      expect(rep.isTrusted, isFalse);
    });

    test('ortalama ve dagilim dogru hesaplanir', () {
      final rep = CollectorReputation.compute([
        _rating(5),
        _rating(4),
        _rating(3),
      ]);
      expect(rep.count, 3);
      expect(rep.average, closeTo(4.0, 1e-9));
      expect(rep.displayScore, '4.0');
      expect(rep.distribution[5], 1);
      expect(rep.distribution[4], 1);
      expect(rep.distribution[3], 1);
    });

    test('GUVENILIR rozeti icin yuksek ortalama TEK BASINA yetmez', () {
      // Tek bir 5 yildiz rozet vermemeli — yoksa rozet anlamsizlasir
      final tekPuan = CollectorReputation.compute([_rating(5)]);
      expect(tekPuan.average, 5.0);
      expect(tekPuan.isTrusted, isFalse,
          reason: 'yeterli teslimat yokken rozet verilemez');

      final yeterli = CollectorReputation.compute([
        _rating(5), _rating(5), _rating(5), _rating(4), _rating(5),
      ]);
      expect(yeterli.count, 5);
      expect(yeterli.isTrusted, isTrue);
      expect(yeterli.label, 'Güvenilir görevli');
    });

    test('cok teslimat ama dusuk ortalama rozet vermez', () {
      final rep = CollectorReputation.compute([
        _rating(3), _rating(2), _rating(4), _rating(3), _rating(5),
        _rating(2),
      ]);
      expect(rep.count, 6);
      expect(rep.isTrusted, isFalse);
      expect(rep.label, '6 değerlendirme');
    });
  });

  group('Rating modeli', () {
    test('toJson requestId ve createdAt TASIMAZ', () {
      // requestId dokuman ID'sinin kendisidir; createdAt'i sunucu yazar.
      final json = _rating(5).toJson();
      expect(json.containsKey('requestId'), isFalse);
      expect(json.containsKey('createdAt'), isFalse);
      expect(json['stars'], 5);
      expect(json['collectorId'], 'c1');
    });

    test('bos yorum JSON a hic yazilmaz', () {
      final json = Rating(
        requestId: 'r1',
        collectorId: 'c1',
        raterId: 'u1',
        stars: 4,
        comment: '   ',
        createdAt: DateTime.now(),
      ).toJson();
      expect(json.containsKey('comment'), isFalse);
    });

    test('bozuk yildiz degeri 1-5 araligina kirpilir', () {
      // Firestore'da bozuk veri olsa bile arayuz cokmemeli
      final tasan = Rating.fromJson('r1', {
        'collectorId': 'c1',
        'raterId': 'u1',
        'stars': 99,
      });
      expect(tasan.stars, 5);

      final eksik = Rating.fromJson('r2', {
        'collectorId': 'c1',
        'raterId': 'u1',
      });
      expect(eksik.stars, 1);
    });
  });

  group('Puanlama formu', () {
    testWidgets('yildiz secilmeden gonderilemez', (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: RatingSheet(
              requestId: 'r1',
              collectorId: 'c1',
              collectorName: 'Test Görevli',
            ),
          ),
        ),
      ));

      expect(find.text('Yıldıza dokunarak puan verin'), findsOneWidget);

      final button = t.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull, reason: 'yildizsiz gonderim kapali');
    });

    testWidgets('yildiza dokununca buton acilir ve etiket degisir', (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: RatingSheet(
              requestId: 'r1',
              collectorId: 'c1',
              collectorName: 'Test Görevli',
            ),
          ),
        ),
      ));

      // 5. yildiza dokun
      await t.tap(find.byTooltip('5 yıldız'));
      await t.pump();

      expect(find.text('Mükemmel'), findsOneWidget);
      final button = t.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('"Şimdi değil" ile gecilebilir (zorunlu degil)', (t) async {
      t.view.physicalSize = const Size(420, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: RatingSheet(
              requestId: 'r1',
              collectorId: 'c1',
              collectorName: 'Test Görevli',
            ),
          ),
        ),
      ));

      expect(find.text('Şimdi değil'), findsOneWidget);
    });
  });
}

// =====================================================================
// REGRESYON — puanlama firsatinin KAYBOLMAMASI
//
// Bulunan kusur: puanlama formunun tek tetikleyicisi vardi (takip ekrani
// ACIKKEN teslimatin tamamlandigini gormek). Kullanici sayfayi yenilerse
// (Ctrl+F5), sekmeyi kapatirsa ya da teslimat baska ekrandayken
// tamamlanirsa firsat KALICI OLARAK kayboluyordu — cunku tamamlanmis
// talep openTracking tarafindan acilmiyor ve gecmis kartlari tiklanamiyordu.
//
// Bu testler kalici yolun (gecmis listesindeki "Puanla" daveti) var
// oldugunu ve dogru talepte ciktigini garanti eder.

WasteRequest _req(RequestStatus status, {String? collectorId}) => WasteRequest(
      id: 'req-${status.name}',
      userId: 'u1',
      wasteTypes: const [WasteType.kagit],
      estimatedKg: 50,
      approxLocation: const LatLng(39.6, 32.1),
      createdAt: DateTime.now(),
      status: status,
      collectorId: collectorId,
      collectorName: 'Toplayici Bir',
    );

Widget _tileHost(WasteRequest r, {Rating? existing}) => ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u1'),
        ratingForRequestProvider
            .overrideWith((ref, id) => Stream.value(existing)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: RatableRequestTile(request: r)),
      ),
    );

void _regression() {
  group('Puanlama firsati KAYBOLMAZ (regresyon)', () {
    testWidgets('TAMAMLANMIS ve puanlanmamis teslimatta "Puanla" cikar',
        (t) async {
      await t.pumpWidget(
        _tileHost(_req(RequestStatus.tamamlandi, collectorId: 'c1')),
      );
      await t.pump();

      expect(find.text('Puanla'), findsOneWidget);
      // Tiklanabilir olmali (ok isareti cizilir)
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('ZATEN puanlanmissa davet YOK, verilen yildiz gorunur',
        (t) async {
      await t.pumpWidget(_tileHost(
        _req(RequestStatus.tamamlandi, collectorId: 'c1'),
        existing: Rating(
          requestId: 'req-tamamlandi',
          collectorId: 'c1',
          raterId: 'u1',
          stars: 4,
          createdAt: DateTime.now(),
        ),
      ));
      await t.pump();

      expect(find.text('Puanla'), findsNothing);
      expect(find.text('4'), findsOneWidget);
      // Tekrar puanlama yok -> tiklanamaz
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('IPTAL edilen talepte puanlama daveti YOK', (t) async {
      await t.pumpWidget(_tileHost(_req(RequestStatus.iptal)));
      await t.pump();
      expect(find.text('Puanla'), findsNothing);
    });

    testWidgets('toplayicisi olmayan tamamlanmis kayitta davet YOK',
        (t) async {
      // Savunmaci: bozuk/eski veride collectorId bos olabilir
      await t.pumpWidget(_tileHost(_req(RequestStatus.tamamlandi)));
      await t.pump();
      expect(find.text('Puanla'), findsNothing);
    });

    testWidgets('AKTIF talepte puanlama daveti YOK', (t) async {
      await t.pumpWidget(_tileHost(_req(RequestStatus.yolda, collectorId: 'c1')));
      await t.pump();
      expect(find.text('Puanla'), findsNothing);
    });
  });
}
