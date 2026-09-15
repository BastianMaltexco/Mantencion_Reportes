import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../data/auth_repository.dart';
import '../domain/authenticated_user.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      AuthRepository(ref.watch(dioProvider), ref.watch(tokenStorageProvider)),
);

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthenticatedUser?>(
      AuthController.new,
    );

class AuthController extends AsyncNotifier<AuthenticatedUser?> {
  @override
  Future<AuthenticatedUser?> build() async {
    ref.listen<int>(sessionExpiredSignalProvider, (previous, next) {
      state = const AsyncData(null);
    });
    return ref.read(authRepositoryProvider).restoreSession();
  }

  Future<void> login(String username, String password) async {
    state = const AsyncLoading();
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .login(username: username, password: password);
      state = AsyncData(user);
    } on AppException catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }
}
