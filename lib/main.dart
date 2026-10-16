import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/auth_gate.dart';
import 'firebase_options.dart';

/// Uygulamanin giris noktasi.
void main() async {
  // Flutter binding'lerinin (native kopruler) hazir olmasini garanti et
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase'i baslat. Yapilandirma (firebase_options.dart) henuz
  // uretilmediyse uygulama COKMEZ: UI modunda acilir, Firestore'a
  // bagli ekranlar kendi hata durumlarini gosterir.
  // `flutterfire configure` calistirilinca bu blok otomatik canlanir.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Yalnizca gelistirmede yazilir: debugPrint yayin derlemesinde
    // ayiklanmaz, bu yuzden kosul ACIKCA konur.
    if (kDebugMode) {
      debugPrint('⚠️ Firebase başlatılamadı (UI modunda devam): $e');
    }
  }

  // ProviderScope: Riverpod'un tum provider'lari yasatabilmesi icin
  // uygulamanin en tepesine konulmasi gereken sarmalayici widget
  runApp(const ProviderScope(child: AtikToplamaApp()));
}

/// Kok (root) uygulama widget'i — tema ve rota yapilandirmasi burada.
class AtikToplamaApp extends StatelessWidget {
  const AtikToplamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ATOS · Atık Toplama Sistemi',
      debugShowCheckedModeBanner: false, // Sag ustteki DEBUG bandini gizle
      // Merkezi tema: renkler, buton bicimleri, kart yuvarlamalari...
      // hepsi core/theme/app_theme.dart'tan gelir
      theme: AppTheme.light,
      // Oturum kapisi: giris yoksa Giris ekrani, varsa rol secimi.
      // Giris/cikis sonrasi ekran KENDILIGINDEN degisir.
      home: const AuthGate(),
    );
  }
}
