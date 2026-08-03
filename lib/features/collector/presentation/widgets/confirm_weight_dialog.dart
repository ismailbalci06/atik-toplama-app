import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../waste_request/domain/models/waste_request_model.dart';

/// Teslim alinan GERCEK miktarin toplayici tarafindan onaylandigi diyalog.
///
/// NEDEN VAR: Kullanicinin talep olustururken girdigi miktar bir BEYANDIR.
/// Yesil Puan ekonomisi beyan uzerine kurulsaydi, kullanici miktari
/// sisirerek puan uretebilirdi. Bu ekran, puanin dogdugu tek noktadir:
/// toplayici kantardaki/gozlemledigi gercek degeri onaylar.
///
/// Iptal edilemez olmasi bilincli — teslimat fiziksel olarak yapildi;
/// geri donusu yok. Toplayici yalnizca miktari duzeltebilir.
Future<double?> showConfirmWeightDialog(
  BuildContext context, {
  required WasteRequest request,
}) {
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConfirmWeightDialog(request: request),
  );
}

class _ConfirmWeightDialog extends StatefulWidget {
  const _ConfirmWeightDialog({required this.request});

  final WasteRequest request;

  @override
  State<_ConfirmWeightDialog> createState() => _ConfirmWeightDialogState();
}

class _ConfirmWeightDialogState extends State<_ConfirmWeightDialog> {
  late final TextEditingController _controller = TextEditingController(
    // Beyan edilen miktar BASLANGIC degeri olarak gelir; toplayici
    // dogruysa onaylar, degilse duzeltir. Bos ekrandan hizli akis.
    text: widget.request.estimatedKg.toStringAsFixed(0),
  );

  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);

    if (value == null || value <= 0) {
      setState(() => _error = 'Geçerli bir miktar girin.');
      return;
    }
    // Kurallardaki 1000 kg ust siniriyla ayni olcek
    if (value > 1000) {
      setState(() => _error = 'Miktar 1000 kg\'ı aşamaz.');
      return;
    }

    Haptics.success();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final declared = widget.request.estimatedKg;

    return PointerInterceptor(
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        ),
        title: const Text('Teslim alınan miktar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Müşteri beyanı: ~${declared.toStringAsFixed(0)} kg. '
              'Gerçekleşen miktarı onaylayın.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Onaylanan miktar',
                suffixText: 'kg',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Müşterinin Yeşil Puanı bu onaylanan miktardan '
                    'hesaplanır.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Onayla ve tamamla'),
          ),
        ],
      ),
    );
  }
}
