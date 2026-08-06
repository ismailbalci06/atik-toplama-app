// GUVENILIRLIK PUANI (Modul A) — karne hesabi ve puanlama formu testleri.
//
// Mimari ilke: ortalama puan HICBIR YERDE SAKLANMAZ, ham puanlardan
// turetilir (Yesil Puan bakiyesiyle ayni felsefe). Bu testler o turetmenin
// dogrulugunu ve "olmayan puani uydurmama" davranisini garanti eder.
import 'package:atik_toplama_app/core/theme/app_theme.dart';
import 'package:atik_toplama_app/features/reputation/domain/collector_reputation.dart';
import 'package:atik_toplama_app/features/reputation/presentation/widgets/rating_sheet.dart';
import 'package:flutter/material.dart';
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
