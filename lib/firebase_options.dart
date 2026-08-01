// =====================================================================
// Firebase yapilandirmasi
// =====================================================================
// Degerler Firebase Console > Proje ayarlari > Web uygulamasi SDK
// config'inden alinmistir (proje: teknofest-projesi-9d218).
//
// NOT: Su an tum platformlar WEB config'ini kullanir — demo web
// uzerinde calistigi icin yeterlidir. Android/iOS'a gecildiginde
// `flutterfire configure` calistirilarak platforma ozel degerler
// bu dosyaya yazilabilir.
// =====================================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    // Mobil platformlarda da (demo amacli) ayni web/genel config kullanilir.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return web;
    }
  }

  /// Web platformu icin Firebase yapilandirmasi
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBT9oHvsO1zADD0XJFfdfP5DIdeCP6OuDg',
    appId: '1:221122601928:web:98ca04726fcf41989396fd',
    messagingSenderId: '221122601928',
    projectId: 'teknofest-projesi-9d218',
    authDomain: 'teknofest-projesi-9d218.firebaseapp.com',
    storageBucket: 'teknofest-projesi-9d218.firebasestorage.app',
    measurementId: 'G-LRTP8LYNL7',
  );
}
