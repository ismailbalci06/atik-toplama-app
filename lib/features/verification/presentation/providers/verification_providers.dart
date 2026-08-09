import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/phone_verification_repository.dart';

final phoneVerificationRepositoryProvider =
    Provider<PhoneVerificationRepository>(
  (ref) => PhoneVerificationRepository(),
);

/// Oturumdaki hesabin DOGRULANMIS telefon numarasi (yoksa null).
///
/// AYRI BIR AKIS olmasi bilincli: `authStateProvider` AuthGate'i besliyor
/// ve uygulamanin giris/cikis akisinin kalbi. Rozeti canli guncellemek
/// icin ona dokunmak yerine kendi `userChanges()` akisimizi dinliyoruz —
/// boylece bu modulun hicbir hatasi oturum akisini etkileyemez.
final verifiedPhoneProvider = StreamProvider.autoDispose<String?>((ref) {
  return ref.watch(phoneVerificationRepositoryProvider).watchVerifiedPhone();
});
