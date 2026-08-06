// TOPLAMA TAKVIMI (Modul B) — tarih hesabi ve hatirlatma testleri.
//
// Kritik nokta: "sonraki toplama gunu" hicbir yerde SAKLANMAZ, plandan
// turetilir. Bu yuzden tarih matematiginin ay/yil tasmalarinda ve
// subatta dogru calismasi zorunlu — saklansaydi bir kez yanlis yazilir
// ve sessizce yanlis kalirdi.
import 'package:atik_toplama_app/features/schedule/domain/pickup_schedule.dart';
import 'package:atik_toplama_app/features/waste_request/domain/models/waste_request_model.dart';
import 'package:flutter_test/flutter_test.dart';

PickupSchedule _schedule({int day = 3, bool active = true}) => PickupSchedule(
      id: 's1',
      userId: 'u1',
      label: 'Aylık kâğıt toplama',
      dayOfMonth: day,
      wasteTypes: const [WasteType.kagit],
      estimatedKg: 120,
      isActive: active,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('nextOccurrence — tarih matematigi', () {
    test('gun HENUZ GELMEDIYSE bu ay', () {
      final next = _schedule(day: 20).nextOccurrence(DateTime(2026, 8, 5));
      expect(next, DateTime(2026, 8, 20));
    });

    test('gun BUGUNSE bugun (kacirilmis sayilmaz)', () {
      final next = _schedule(day: 5).nextOccurrence(DateTime(2026, 8, 5));
      expect(next, DateTime(2026, 8, 5));
    });

    test('gun GECTIYSE gelecek ay', () {
      final next = _schedule(day: 3).nextOccurrence(DateTime(2026, 8, 5));
      expect(next, DateTime(2026, 9, 3));
    });

    test('YIL TASMASI: aralik -> ocak', () {
      final next = _schedule(day: 3).nextOccurrence(DateTime(2026, 12, 10));
      expect(next, DateTime(2027, 1, 3));
    });

    test('SUBAT guvenli: 28 ust siniri sayesinde kayma yok', () {
      // dayOfMonth en fazla 28 olabildigi icin subatta bile gecerli
      final next = _schedule(day: 28).nextOccurrence(DateTime(2027, 2, 1));
      expect(next, DateTime(2027, 2, 28));
      expect(PickupSchedule.maxDayOfMonth, 28);
    });

    test('bozuk veri 1-28 araligina kirpilir', () {
      final tasan = PickupSchedule.fromJson('x', {
        'userId': 'u1',
        'dayOfMonth': 31,
        'wasteTypes': ['kagit'],
        'estimatedKg': 50,
      });
      expect(tasan.dayOfMonth, 28);

      final sifir = PickupSchedule.fromJson('y', {
        'userId': 'u1',
        'dayOfMonth': 0,
        'wasteTypes': ['kagit'],
        'estimatedKg': 50,
      });
      expect(sifir.dayOfMonth, 1);
    });
  });

  group('Hatirlatma penceresi', () {
    test('bugunse 0 gun ve BUGUN metni', () {
      final s = _schedule(day: 5);
      expect(s.daysUntil(DateTime(2026, 8, 5)), 0);
      expect(s.reminderText(DateTime(2026, 8, 5)), contains('BUGÜN'));
      expect(s.isDueSoon(DateTime(2026, 8, 5)), isTrue);
    });

    test('yarinsa "yarın" denir', () {
      final s = _schedule(day: 6);
      expect(s.daysUntil(DateTime(2026, 8, 5)), 1);
      expect(s.reminderText(DateTime(2026, 8, 5)), contains('yarın'));
    });

    test('pencere disindaysa hatirlatma YOK', () {
      // 3 gunluk pencere: 10 gun sonrasi icin serit cizilmemeli
      final s = _schedule(day: 15);
      expect(s.daysUntil(DateTime(2026, 8, 5)), 10);
      expect(s.isDueSoon(DateTime(2026, 8, 5)), isFalse);
    });

    test('pencerenin tam sinirinda hatirlatma VAR', () {
      final s = _schedule(day: 8);
      expect(s.daysUntil(DateTime(2026, 8, 5)), 3);
      expect(s.isDueSoon(DateTime(2026, 8, 5)), isTrue);
    });
  });

  group('Takvim baglantisi', () {
    test('AYLIK TEKRAR kurali ve dogru gun icerir', () {
      final url = _schedule(day: 12).googleCalendarUrl();
      expect(url, startsWith('https://calendar.google.com/calendar/render?'));
      expect(url, contains('FREQ%3DMONTHLY'));
      expect(url, contains('BYMONTHDAY%3D12'));
    });

    test('baslik ve ozet kacislanmis olarak gecer', () {
      final url = _schedule().googleCalendarUrl();
      // Turkce karakterler ve bosluklar URL-encode edilmeli
      expect(url, contains('ATOS'));
      expect(url.contains(' '), isFalse,
          reason: 'kacislanmamis bosluk baglantiyi bozar');
    });
  });

  group('Ozet metni', () {
    test('tur, miktar ve gun birlikte yazilir', () {
      final s = _schedule(day: 7);
      expect(s.summary, contains('Kâğıt'));
      expect(s.summary, contains('120 kg'));
      expect(s.summary, contains("her ayın 7"));
    });
  });

  group('toJson', () {
    test('createdAt TASIMAZ (sunucu saati yazar)', () {
      final json = _schedule().toJson();
      expect(json.containsKey('createdAt'), isFalse);
      expect(json['dayOfMonth'], 3);
      expect(json['isActive'], isTrue);
    });
  });
}
