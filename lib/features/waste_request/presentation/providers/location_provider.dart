import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Kullanicinin anlik GPS konumunu getiren FutureProvider.
///
/// - Konum servisi kapaliysa veya izin reddedildiyse hata firlatir;
///   UI tarafi bu hatayi AsyncValue.error olarak yakalayip kullaniciya gosterir.
/// - Basarili olursa haritanin merkezleyecegi [LatLng] degerini dondurur.
final userLocationProvider = FutureProvider<LatLng>((ref) async {
  // 1) Cihazda konum servisi (GPS) acik mi kontrol et
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Konum servisi kapalı. Lütfen GPS\'i açın.');
  }

  // 2) Uygulamanin konum iznini kontrol et, yoksa iste
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Konum izni reddedildi.');
    }
  }
  if (permission == LocationPermission.deniedForever) {
    throw Exception(
        'Konum izni kalıcı olarak reddedilmiş. Ayarlardan izin verin.');
  }

  // 3) Guncel konumu al ve LatLng olarak dondur
  final position = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
  return LatLng(position.latitude, position.longitude);
});
