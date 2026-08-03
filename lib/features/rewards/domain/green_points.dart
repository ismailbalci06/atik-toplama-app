import '../../impact/domain/impact_stats.dart';
import '../../waste_request/domain/models/waste_request_model.dart';

/// ATOS Yesil Puan ekonomisi.
///
/// TASARIM ILKELERI (juriye savunulabilir olmasi icin):
///
/// 1. PUAN UYDURMA KATSAYIYA DAYANMAZ. Puan, zaten belgelenmis
///    [ImpactStats.co2PerKg] tablosundan hesaplanan ONLENEN CO2'ye
///    orantilidir. Boylece "metal neden daha cok puan?" sorusunun cevabi
///    pazarlama degil, karbon tablosudur (metal 4.0 vs cam 0.3 kg CO2e/kg).
///
/// 2. PUAN BEYANDAN DEGIL ONAYDAN DOGAR. Yalnizca toplayicinin teslim
///    alirken onayladigi [WasteRequest.confirmedKg] sayilir. Kullanicinin
///    kendi yazdigi tahmini miktar puan uretmez — aksi halde slider'i
///    250 kg'a cekip puan basmak mumkun olurdu.
///
/// 3. BAKIYE HICBIR YERDE SAKLANMAZ. Yazilabilir bir "puan" alani yoktur;
///    bakiye her seferinde kazanilan eksi harcanan olarak TURETILIR. Boylece
///    kimsenin degistirebilecegi bir bakiye alani da yoktur.
class GreenPoints {
  GreenPoints._();

  /// 1 kg onlenen CO2 = 10 Yesil Puan.
  ///
  /// Carpanin kendisi tamamen kurgusaldir (bir para birimi degildir) ama
  /// DAGILIMI gercek karbon verisinden gelir. Odul fiyatlari da bu olcege
  /// gore belirlenir.
  static const int pointsPerCo2Kg = 10;

  /// Bir teslimatin kazandirdigi puan.
  ///
  /// Onaylanmamis (confirmedKg == null) teslimat SIFIR puan getirir —
  /// bu bilincli: onay yoksa olculmus bir is de yoktur.
  static int forRequest(WasteRequest r) {
    final kg = r.confirmedKg;
    if (kg == null || kg <= 0) return 0;
    if (r.status != RequestStatus.tamamlandi) return 0;
    if (r.wasteTypes.isEmpty) return 0;

    // Talebin kg'i secili turlere esit dagitilir — ImpactStats ile AYNI
    // varsayim (model tur basina kg tutmuyor). Iki yerde ayni varsayimi
    // kullanmak, rapor ile puanin birbirini tutmasini garanti eder.
    final perType = kg / r.wasteTypes.length;
    var co2 = 0.0;
    for (final t in r.wasteTypes) {
      co2 += perType * (ImpactStats.co2PerKg[t] ?? 0);
    }
    return (co2 * pointsPerCo2Kg).round();
  }

  /// Kullanicinin bugune kadar KAZANDIGI toplam puan.
  static int earned(List<WasteRequest> requests) =>
      requests.fold(0, (sum, r) => sum + forRequest(r));
}

/// Tesis seviyesi — kazanilan toplam puana gore otomatik yukselir.
///
/// Harcanan puan seviyeyi DUSURMEZ: seviye "ne kadar is yaptin" demektir,
/// "cuzdaninda ne var" demek degil. Odul harcamak rozetini geri almaz.
enum FacilityTier {
  bronz('Bronz Tesis', '🥉', 0),
  gumus('Gümüş Tesis', '🥈', 2000),
  altin('Altın Tesis', '🥇', 8000),
  platin('Platin Tesis', '💎', 20000);

  const FacilityTier(this.label, this.emoji, this.threshold);

  /// Kullaniciya gosterilecek ad
  final String label;

  /// Rozet ikonu
  final String emoji;

  /// Bu seviyeye gecmek icin gereken KAZANILMIS toplam puan
  final int threshold;

  /// Toplam kazanilan puana karsilik gelen seviye
  static FacilityTier forPoints(int earnedPoints) {
    var current = FacilityTier.bronz;
    for (final t in FacilityTier.values) {
      if (earnedPoints >= t.threshold) current = t;
    }
    return current;
  }

  /// Bir sonraki seviye (en ustteyse null)
  FacilityTier? get next {
    final i = index + 1;
    return i < FacilityTier.values.length ? FacilityTier.values[i] : null;
  }

  /// Bir sonraki seviyeye ilerleme orani (0-1). En ustte 1 doner.
  double progressTo(int earnedPoints) {
    final upper = next;
    if (upper == null) return 1;
    final span = upper.threshold - threshold;
    if (span <= 0) return 1;
    return ((earnedPoints - threshold) / span).clamp(0.0, 1.0);
  }
}

/// Kullanicinin puan cuzdaninin ANLIK ozeti.
/// Hicbir alani Firestore'da saklanmaz; hepsi canli veriden turetilir.
class PointsWallet {
  const PointsWallet({
    required this.earned,
    required this.spent,
    required this.confirmedDeliveries,
  });

  /// Onaylanmis teslimatlardan kazanilan toplam
  final int earned;

  /// Odul taleplerine (beklemede + onaylanmis) ayrilan toplam.
  ///
  /// Beklemedekiler de dusulur: kullanici ayni puani iki odule birden
  /// harcayamaz. Talep reddedilirse puan kendiliginden geri gelir.
  final int spent;

  /// Puan ureten (onaylanmis) teslimat sayisi
  final int confirmedDeliveries;

  static const empty =
      PointsWallet(earned: 0, spent: 0, confirmedDeliveries: 0);

  /// Harcanabilir bakiye
  int get balance => earned - spent;

  /// Kazanilan puana gore tesis seviyesi
  FacilityTier get tier => FacilityTier.forPoints(earned);
}
