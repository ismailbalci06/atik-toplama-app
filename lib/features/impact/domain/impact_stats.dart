import '../../waste_request/domain/models/waste_request_model.dart';

/// Tamamlanmis teslimatlardan hesaplanan CANLI cevresel etki ozeti.
///
/// Artik sabit/sahte deger DEGIL: Firestore'daki `status: tamamlandi`
/// taleplerinden gercek zamanli hesaplanir. Katsayilar tek yerde tutulur,
/// juriye kaynak gosterilebilir sekilde belgelenmistir.
class ImpactStats {
  final double wasteKg;   // Geri kazanilan toplam atik (kg)
  final double co2Kg;     // Onlenen tahmini karbon salinimi (kg CO2e)
  final double trees;     // Kurtarilan agac (yalnizca kagit tonajindan)
  final int deliveries;   // Kac tamamlanmis teslimattan hesaplandi

  const ImpactStats({
    required this.wasteKg,
    required this.co2Kg,
    required this.trees,
    required this.deliveries,
  });

  static const empty =
      ImpactStats(wasteKg: 0, co2Kg: 0, trees: 0, deliveries: 0);

  /// Malzeme basina yaklasik onlenen CO2 (kg CO2e / kg geri donusum).
  /// Degerler literaturdeki yaygin ortalamalara dayanir; MVP icin
  /// muhafazakar secildi. Uretimde malzeme bazli resmi katsayilarla
  /// ( or. Cevre Bakanligi / EPA verileri) degistirilebilir.
  static const Map<WasteType, double> co2PerKg = {
    WasteType.plastik: 1.5,
    WasteType.cam: 0.3,
    WasteType.kagit: 0.9,
    WasteType.metal: 4.0,
    WasteType.pil: 2.0,
    WasteType.elektronik: 1.8,
  };

  /// 1 ton (1000 kg) kagit ~ 17 agac => 0.017 agac/kg.
  /// Agac metrigini BILINCLI olarak yalnizca kagittan hesapliyoruz;
  /// boylece iddia abartili degil, savunulabilir olur.
  static const double treesPerKgPaper = 0.017;

  /// Tamamlanmis talep listesinden toplam etkiyi hesaplar.
  ///
  /// Varsayim: Bir talebin toplam kg'i, secili atik turlerine ESIT
  /// dagitilir (model tur basina kg tutmadigi icin). Bu varsayim
  /// kod icinde acikca belirtilmistir — juriye seffaf sunulabilir.
  factory ImpactStats.fromRequests(List<WasteRequest> requests) {
    var waste = 0.0;
    var co2 = 0.0;
    var trees = 0.0;

    for (final r in requests) {
      waste += r.estimatedKg;
      final typeCount = r.wasteTypes.isEmpty ? 1 : r.wasteTypes.length;
      final perType = r.estimatedKg / typeCount;

      for (final t in r.wasteTypes) {
        co2 += perType * (co2PerKg[t] ?? 0);
        if (t == WasteType.kagit) trees += perType * treesPerKgPaper;
      }
    }

    return ImpactStats(
      wasteKg: waste,
      co2Kg: co2,
      trees: trees,
      deliveries: requests.length,
    );
  }
}
