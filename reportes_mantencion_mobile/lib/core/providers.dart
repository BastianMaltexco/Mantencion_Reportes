import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_config.dart';
import 'network/api_client.dart';
import 'network/secure_token_storage.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
final tokenStorageProvider = Provider<SecureTokenStorage>(
  (ref) => SecureTokenStorage(),
);

/// Se incrementa al vencer una sesión que no puede renovarse.
final sessionExpiredSignalProvider =
    NotifierProvider<SessionExpiredNotifier, int>(SessionExpiredNotifier.new);

class SessionExpiredNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void expire() => state++;
}

final dioProvider = Provider<Dio>((ref) {
  final client = ApiClient(ref.watch(tokenStorageProvider), () {
    ref.read(sessionExpiredSignalProvider.notifier).expire();
  }, config: ref.watch(appConfigProvider));
  return client.dio;
});
