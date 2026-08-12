import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// OPENSTREETMAP ATIF ETIKETI — YASAL ZORUNLULUK, CILA DEGIL.
///
/// Rota geometrisi OSRM'den gelir, OSRM ise OpenStreetMap verisini kullanir.
/// OSM verisi ODbL 1.0 ile lisanslidir ve turetilmis gorsellestirmede
/// KAYNAK ATFI ZORUNLUDUR. Bu yuzden bu etiket, OSRM rotasi cizen HER
/// ekranda gorunmek zorundadir (su an: toplayici haritasi + takip ekrani).
///
/// Silmeyin/gizlemeyin: kaldirilmasi lisans ihlalidir. Yarisma sartnamesi
/// madde 10.4 de atif gerektiren bilesenlerin beyanini istiyor.
///
/// YERLESIM KURALI — bunu degistirmeden once oku:
/// Google'in kendi atfi (sol altta logo, sag altta "Harita verileri ©...")
/// Maps hizmet sartlarinin geregidir ve KAPATILAMAZ. Bu etiket o yuzden alt
/// seritte yer kapmaya CALISMAZ; seridin BIRAZ USTUNDE (bottom: 24) durur.
/// Boylece Google'in ogelerinin genisligini bilmeye gerek kalmaz — hangi
/// ekran genisliginde olursa olsun cakisma olmaz. Alt kartlar da bu etikete
/// yer acmak icin 24 -> 46 seviyesine tasindi.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          // Yari saydam beyaz: harita hem okunur kalir hem etiket kaybolmaz.
          color: Colors.white.withOpacity(0.82),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Rota verisi © OpenStreetMap katkıcıları',
          style: TextStyle(
            fontSize: 9,
            height: 1.2,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
