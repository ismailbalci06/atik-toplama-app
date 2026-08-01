import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/waste_request_providers.dart';
import '../widgets/request_tile.dart';

/// 'Taleplerim' — kullanicinin GECMIS taleplerinin canli listesi.
///
/// Veri dogrudan Firestore'dan ([userRequestsProvider]) gelir ve artik
/// GERCEK kullanici UID'sine gore filtrelenir (eskiden sabit demo ID idi).
///
/// [embedded] true iken alt navigasyon kabugu icinde calisir: kendi
/// AppBar'ini cizer ama geri butonu gostermez.
class RequestHistoryScreen extends ConsumerWidget {
  const RequestHistoryScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    final requestsAsync = ref.watch(userRequestsProvider(userId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Taleplerim'),
        automaticallyImplyLeading: !embedded,
      ),
      body: requestsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Talepler yüklenemedi: $e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (requests) {
          if (requests.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => RequestTile(request: requests[i]),
          );
        },
      ),
    );
  }
}

/// Hic talep yoksa gosterilen bos durum
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.inbox_outlined,
                  size: 30, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Text('Henüz talebiniz yok',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Oluşturduğunuz talepler burada kalıcı olarak listelenir.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
