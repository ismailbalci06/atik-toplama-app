import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/web_focus.dart';
import '../../domain/models/waste_request_model.dart';

/// Alt kisimdan acilan "Atik Talebi Olusturma" formu.
///
/// [showWasteRequestSheet] yardimci fonksiyonu ile acilir.
/// Kullanici formu doldurup onayladiginda geriye bir [WasteRequest]
/// nesnesi doner; iptal ederse null doner.
Future<WasteRequest?> showWasteRequestSheet(
  BuildContext context, {
  required LatLng location, // Haritada secilen/mevcut konum
  required String userId,   // Talebi olusturan kullanicinin gercek UID'si
}) {
  return showModalBottomSheet<WasteRequest>(
    context: context,
    isScrollControlled: true, // Klavye acilinca sheet'in yukselebilmesi icin
    backgroundColor: Colors.transparent,
    builder: (_) => WasteRequestBottomSheet(location: location, userId: userId),
  );
}

class WasteRequestBottomSheet extends StatefulWidget {
  const WasteRequestBottomSheet({
    super.key,
    required this.location,
    required this.userId,
  });

  /// Talebin olusturulacagi koordinat (haritadan gelir)
  final LatLng location;

  /// Talebi olusturan kullanicinin Firebase UID'si
  final String userId;

  @override
  State<WasteRequestBottomSheet> createState() =>
      _WasteRequestBottomSheetState();
}

class _WasteRequestBottomSheetState extends State<WasteRequestBottomSheet> {
  /// Kullanicinin sectigi atik turleri (coklu secim destekli)
  final Set<WasteType> _selectedTypes = {};

  /// Tahmini agirlik — slider ile 5-250 kg arasi, 5 kg adimlarla secilir.
  /// (B2B olcegi: site/isletme deposunda biriken TOPLU atik miktari.)
  double _estimatedKg = 50;

  /// Opsiyonel not alani icin controller
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Sheet acilir acilmaz DOM odagini haritadan al (Flutter Web).
    // Aksi halde ok tuslari haritaya gider ve harita kayar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      releaseDomFocusFromMap();
    });
  }

  @override
  void dispose() {
    // Memory leak olmamasi icin controller'i temizle
    _noteController.dispose();
    super.dispose();
  }

  /// Miktari [delta] kadar degistirir (5-250 kg araliginda tutar).
  void _changeKg(double delta) {
    Haptics.tap();
    releaseDomFocusFromMap(); // odak haritaya kacmasin
    setState(() {
      _estimatedKg = (_estimatedKg + delta).clamp(5, 250);
    });
  }

  /// "Talep Olustur" butonuna basildiginda calisir.
  /// Formu dogrular, WasteRequest nesnesi uretir ve sheet'i kapatarak
  /// nesneyi cagirana (harita ekranina) geri dondurur.
  void _submitRequest() {
    // En az bir atik turu secilmis olmali
    if (_selectedTypes.isEmpty) {
      Haptics.tap(); // Uyari icin hafif dokunus
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen en az bir atık türü seçin.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    Haptics.action(); // Talep olusturma onayi

    final request = WasteRequest(
      id: const Uuid().v4(), // Benzersiz talep ID'si
      userId: widget.userId, // gercek Firebase UID
      wasteTypes: _selectedTypes.toList(),
      estimatedKg: _estimatedKg,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      location: widget.location,
      createdAt: DateTime.now(),
    );

    // Sheet'i kapat ve olusturulan talebi geri dondur
    Navigator.of(context).pop(request);
  }

  @override
  Widget build(BuildContext context) {
    // Klavye acildiginda formun klavyenin altinda kalmamasi icin padding
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // PointerInterceptor: Flutter Web'de bu kartin uzerindeki tiklama ve
    // suruklemelerin ARKADAKI Google Haritalar (HTML platform view) katmanina
    // sizmasini engeller. Bu olmadan slider topuzunu surukleyince harita da
    // kayiyor. Web disinda hicbir etkisi yoktur (seffaf gecer).
    return PointerInterceptor(
      child: Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Surukleme cubugu (grab handle) ---
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // --- Baslik ---
              const Text(
                'Atık Talebi Oluştur',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Atık türünü ve tahmini toplu miktarı seçin, aracımız gelsin.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              // --- Atik turu secimi (coklu secim chip'leri) ---
              const Text(
                'Atık Türü',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                // Enum uzerinden otomatik chip listesi uretilir;
                // yeni tur eklemek icin sadece enum'a eklemek yeterli
                children: WasteType.values.map((type) {
                  final isSelected = _selectedTypes.contains(type);
                  return FilterChip(
                    label: Text('${type.emoji} ${type.label}'),
                    selected: isSelected,
                    selectedColor: AppColors.secondary.withOpacity(0.25),
                    checkmarkColor: AppColors.primary,
                    onSelected: (selected) {
                      // Secim durumunu guncelle ve UI'i yeniden ciz
                      setState(() {
                        selected
                            ? _selectedTypes.add(type)
                            : _selectedTypes.remove(type);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // --- Tahmini miktar (slider) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tahmini Miktar',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  // Adim butonlari: ok tusuna hic gerek kalmadan hassas ayar
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed:
                            _estimatedKg > 5 ? () => _changeKg(-5) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        color: AppColors.primary,
                        tooltip: '5 kg azalt',
                        visualDensity: VisualDensity.compact,
                      ),
                      SizedBox(
                        width: 62,
                        child: Text(
                          '~${_estimatedKg.toStringAsFixed(0)} kg',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed:
                            _estimatedKg < 250 ? () => _changeKg(5) : null,
                        icon: const Icon(Icons.add_circle_outline),
                        color: AppColors.primary,
                        tooltip: '5 kg artır',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
              Slider(
                value: _estimatedKg,
                min: 5,
                max: 250,
                // 49 bolme => tam 5 kg'lik adimlar (5, 10, 15 ... 250)
                divisions: 49,
                activeColor: AppColors.primary,
                label: '${_estimatedKg.toStringAsFixed(0)} kg',
                // autofocus: sheet acilinca klavye odagi Flutter'a gecer;
                // boylece ok tuslari haritayi degil SADECE slider'i hareket
                // ettirir (Flutter Web'de harita HTML ogesinin ok tuslariyla
                // kaymasini onler).
                autofocus: true,
                // Slider'a her dokunusta DOM odagini haritadan geri al
                onChangeStart: (_) => releaseDomFocusFromMap(),
                onChanged: (value) => setState(() => _estimatedKg = value),
              ),
              const SizedBox(height: 8),

              // --- Opsiyonel not alani ---
              TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Not (opsiyonel)',
                  hintText: 'Örn: Kapıcıya bırakılacak, 3. kat...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- Talep Olustur butonu ---
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.recycling),
                  label: const Text(
                    'Talep Oluştur',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
