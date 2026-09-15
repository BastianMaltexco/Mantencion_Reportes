import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionTokens {
  const SessionTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// Contrato mínimo del almacén cifrado que usa el cliente HTTP.
///
/// Separarlo de la implementación permite verificar que las solicitudes de
/// adjuntos usan y renuevan el JWT sin reemplazar el almacenamiento seguro en
/// producción.
abstract interface class TokenStorage {
  Future<SessionTokens?> read();
  Future<void> save(SessionTokens tokens);
  Future<void> clear();
}

/// Wrapper central para impedir que los tokens terminen en SharedPreferences
/// convencionales, archivos de configuración o registros de depuración.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'reportes_mantencion_tokens_v1',
              migrateWithBackup: true,
            ),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  static const _accessKey = 'reportes_access_token';
  static const _refreshKey = 'reportes_refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<SessionTokens?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    if (access == null ||
        access.isEmpty ||
        refresh == null ||
        refresh.isEmpty) {
      return null;
    }
    return SessionTokens(accessToken: access, refreshToken: refresh);
  }

  @override
  Future<void> save(SessionTokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    await _storage.write(key: _refreshKey, value: tokens.refreshToken);
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}
