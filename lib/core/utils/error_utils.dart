import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Herhangi bir hatayi kullaniciya/konsola gosterilebilecek GUVENLI bir
/// string'e cevirir.
///
/// NEDEN GEREKLI?
/// Flutter Web'de bir [FirebaseException] yakalanip dogrudan string
/// enterpolasyonuna (`'$e'`) veya bir JS koprusune verildiginde
/// `type 'FirebaseException' is not a subtype of type 'JavaScriptObject'`
/// tipi bir cokme olusabiliyor. Cozum: hata nesnesini ASLA ham haliyle
/// kullanma; her zaman once bu fonksiyonla guvenli string'e cevir.
///
/// Ayrica FirebaseException'in ic alanlarini (code + message) acarak
/// alttaki ASIL hatayi (izin reddi, eksik alan vb.) net gosterir.
String readableError(Object error) {
  final raw = error.toString();

  // OZEL DURUM: Firebase henuz yapilandirilmadi.
  // firebase_options.dart yer tutucuysa Firebase.initializeApp calismaz;
  // sonraki Firestore cagrilari '[core/no-app]' verir ve Web'de bu,
  // "...FirebaseException is not a subtype of JavaScriptObject" seklinde
  // anlasilmaz bir TypeError'a donusur. Ikisini de net mesaja ceviriyoruz.
  if (raw.contains('JavaScriptObject') ||
      raw.contains('core/no-app') ||
      raw.contains('No Firebase App')) {
    return 'Firebase yapılandırılmadı. Gerçek zamanlı özellikler için '
        '`flutterfire configure` çalıştırılmalı (firebase_options.dart '
        'henüz üretilmedi).';
  }

  if (error is FirebaseException) {
    // Orn: "[permission-denied] Missing or insufficient permissions."
    final message = error.message ?? error.code;
    return '[${error.code}] $message';
  }
  // Diger hatalar: "Exception: " on ekini temizleyerek sadece goster
  return raw.replaceFirst('Exception: ', '');
}

/// Hatayi hem gelistirici konsoluna basar (debug) hem de kullaniciya
/// gosterilecek guvenli string'i dondurur. Catch bloklarinda tek satirda
/// hem loglama hem mesaj uretmek icin kullanilir.
String logAndReadError(Object error, {String? context}) {
  final readable = readableError(error);
  debugPrint('🔥 Firestore hatası${context == null ? '' : ' ($context)'}: '
      '$readable');
  return readable;
}
