// GIZLILIK MASKELEMESI (KVKK) — regresyon testleri.
//
// Kapatilan zafiyet: acik adres (tam koordinat) ve kullanici notu, herkesin
// okuyabildigi ana dokumanda duruyordu. Artik korumali alt dokumandalar.
//
// Buradaki en kritik test `toJson` testidir: ana dokumana yazilan haritada
// 'note' veya 'location' anahtari ASLA bulunmamalidir. Firestore kurali da
// ayni sarti sunucuda uygular — bu test, kurala hic gitmeden once hatayi
// derleme/test asamasinda yakalar.
import 'package:atik_toplama_app/features/collector/presentation/widgets/request_detail_sheet.dart';
import 'package:atik_toplama_app/features/waste_request/domain/models/waste_request_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  const exact = LatLng(39.573412, 32.147891);

  group('Konum maskeleme (izgara yuvarlamasi)', () {
    test('yaklasik konum tam konumdan FARKLI olur', () {
      final approx = snapToPrivacyGrid(exact);
      expect(approx.latitude, isNot(equals(exact.latitude)));
    });

    test('DETERMINISTIK: ayni girdi hep ayni hucreye duser', () {
      // Rastgele kaydirma olsaydi, tekrar tekrar okuyup ortalama alan biri
      // gercek konumu geri hesaplayabilirdi. Izgara buna kapalidir.
      final a = snapToPrivacyGrid(exact);
      final b = snapToPrivacyGrid(exact);
      expect(a.latitude, b.latitude);
      expect(a.longitude, b.longitude);
    });

    test('gercek nokta, maskeleme cemberinin (500 m) icinde kalir', () {
      final approx = snapToPrivacyGrid(exact);
      // Yarim hucre = 0.0025 derece; enlemde ~278 m, boylamda daha az.
      expect((approx.latitude - exact.latitude).abs(),
          lessThanOrEqualTo(kLocationGridStep / 2 + 1e-9));
      expect((approx.longitude - exact.longitude).abs(),
          lessThanOrEqualTo(kLocationGridStep / 2 + 1e-9));
    });
  });

  group('Acik dokumanda hassas veri OLMAMALI', () {
    test('WasteRequest.toJson icinde note ve location anahtarlari yok', () {
      final json = WasteRequest(
        id: 'r1',
        userId: 'u1',
        wasteTypes: const [WasteType.plastik],
        estimatedKg: 80,
        approxLocation: snapToPrivacyGrid(exact),
        createdAt: DateTime.now(),
      ).toJson();

      expect(json.containsKey('note'), isFalse,
          reason: 'Kullanici notu acik dokumana yazilamaz');
      expect(json.containsKey('location'), isFalse,
          reason: 'Tam koordinat acik dokumana yazilamaz');
      expect(json.containsKey('approxLocation'), isTrue);

      // Yazilan konum gercekten yuvarlanmis olmali
      final geo = json['approxLocation'] as GeoPoint;
      expect(geo.latitude, isNot(equals(exact.latitude)));
    });

    test('RequestDetail hassas alanlari tasir ve geri okunur', () {
      final detail = RequestDetail(
        ownerId: 'u1',
        exactLocation: exact,
        note: 'Kapıcıya bırakılacak, 3. kat',
      );
      final back = RequestDetail.fromJson(detail.toJson());

      expect(back.ownerId, 'u1');
      expect(back.exactLocation.latitude, closeTo(exact.latitude, 1e-9));
      expect(back.note, 'Kapıcıya bırakılacak, 3. kat');
    });

    test('ESKI kayitlar (location alanli) okunurken yuvarlanir', () {
      // Gizlilik yamasindan onceki dokumanlar tam koordinati 'location'
      // alaninda tasiyor; arayuz onlari da maskeli gostermeli.
      final r = WasteRequest.fromJson('eski', {
        'userId': 'u1',
        'wasteTypes': ['plastik'],
        'estimatedKg': 50,
        'location': GeoPoint(exact.latitude, exact.longitude),
        'status': 'bekliyor',
      });

      expect(r.approxLocation.latitude, isNot(equals(exact.latitude)));
      expect(r.approxLocation.latitude,
          equals(snapToPrivacyGrid(exact).latitude));
    });
  });

  group('Toplayici detay karti', () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    final request = WasteRequest(
      id: 'r1',
      userId: 'u1',
      wasteTypes: const [WasteType.plastik],
      estimatedKg: 80,
      approxLocation: snapToPrivacyGrid(exact),
      createdAt: DateTime.now(),
    );

    testWidgets('talep ALINMADAN once: not gizli, maske aciklamasi var',
        (t) async {
      t.view.physicalSize = const Size(500, 1000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(wrap(RequestDetailSheet(
        request: request,
        distanceKm: 2.4,
        isAccepted: false,
        detail: null, // yetkimiz yok -> veri elimizde YOK
      )));

      expect(find.textContaining('yaklaşık bölge'), findsOneWidget);
      expect(find.textContaining('Kapıcıya'), findsNothing);
      // Mesafe de yaklasik oldugunu soylemeli
      expect(find.textContaining('≈'), findsOneWidget);
    });

    testWidgets('talep ALINDIKTAN sonra: not gorunur, maske yazisi yok',
        (t) async {
      t.view.physicalSize = const Size(500, 1000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);

      await t.pumpWidget(wrap(RequestDetailSheet(
        request: request,
        distanceKm: 2.4,
        isAccepted: true,
        detail: RequestDetail(
          ownerId: 'u1',
          exactLocation: exact,
          note: 'Kapıcıya bırakılacak',
        ),
      )));

      expect(find.textContaining('Kapıcıya bırakılacak'), findsOneWidget);
      expect(find.textContaining('yaklaşık bölge'), findsNothing);
    });
  });
}
