import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../waste_request/presentation/providers/waste_request_providers.dart';
import '../../data/auth_repository.dart';

/// Auth erisim katmaninin tek ornegi
final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository());

/// Oturum durumu — giris/cikis oldugunda tum uygulama otomatik tepki verir.
/// AuthGate bunu dinleyerek Giris ekrani mi yoksa uygulama mi gosterecegine
/// karar verir.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Giris yapmis kullanici (yoksa null)
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// Firestore kayitlarinda kullanilacak KULLANICI ID'si.
/// Oturum yoksa bos string doner (bu durumda zaten Giris ekrani gosterilir).
final currentUserIdProvider = Provider<String>((ref) {
  return ref.watch(currentUserProvider)?.uid ?? '';
});

/// Karsilama metninde kullanilacak ad.
/// Kayit sirasinda girilen ad yoksa e-postanin ilk parcasina duser.
final currentUserNameProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  final name = user?.displayName?.trim();
  if (name != null && name.isNotEmpty) return name.split(' ').first;
  final email = user?.email;
  if (email != null && email.contains('@')) return email.split('@').first;
  return 'Kullanıcı';
});

/// GUVENLI CIKIS — tek dogru yol.
///
/// NEDEN AYRI BIR YARDIMCI?
/// Sadece `signOut()` cagirmak YETMIYOR ve gercek bir hataya yol aciyordu:
/// AuthGate oturum akisini dinledigi icin ALTTA Giris ekranini cizer, ama
/// kullanicinin gordugu Dashboard/Profil ekranlari Navigator yiginin da
/// USTTE durmaya devam eder. Sonuc: cikis yapilmis ama eski ekran acikta
/// kalir; kullanici bilgisi null oldugu icin "Merhaba, Kullanıcı" ve bos/
/// karisik veriler gorunur.
///
/// Bu fonksiyon uc isi birlikte yapar:
///   1. Oturumu kapatir
///   2. Kullaniciya ozel provider onbelleklerini temizler (state sizintisi yok)
///   3. Navigator yigini KOKE kadar bosaltir -> ekranda yalnizca AuthGate kalir
Future<void> signOutAndReset(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  await ref.read(authRepositoryProvider).signOut();

  // Kullaniciya ozel tum aile (family) ornekleri dusurulur
  ref.invalidate(userRequestsProvider);
  ref.invalidate(requestByIdProvider);
  ref.invalidate(pendingRequestsProvider);

  // Ustte kalan tum ekranlari kapat: geriye yalnizca AuthGate kalir
  navigator.popUntil((route) => route.isFirst);
}
