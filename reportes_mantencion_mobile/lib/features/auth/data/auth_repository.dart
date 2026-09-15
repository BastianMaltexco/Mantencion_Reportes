import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/secure_token_storage.dart';
import '../domain/authenticated_user.dart';

class AuthRepository {
  AuthRepository(this._dio, this._tokenStorage);

  final Dio _dio;
  final SecureTokenStorage _tokenStorage;

  Future<AuthenticatedUser> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'username': username.trim(),
          'password': password,
          'client_name': 'Flutter mobile',
        },
        options: Options(extra: const {'skipAuth': true, 'skipRefresh': true}),
      );
      final data = _envelope(response.data);
      await _saveTokens(data);
      return AuthenticatedUser.fromJson(
        Map<String, dynamic>.from(data['user'] as Map),
      );
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }

  /// Recupera la sesión persistida y la valida contra la API.
  Future<AuthenticatedUser?> restoreSession() async {
    if (await _tokenStorage.read() == null) return null;
    try {
      return await me();
    } on AppException {
      await _tokenStorage.clear();
      return null;
    }
  }

  Future<AuthenticatedUser> me() async {
    try {
      // El contrato desplegado expone el perfil en /auth/me.
      final response = await _dio.get<Map<String, dynamic>>('/auth/me');
      return AuthenticatedUser.fromJson(_envelope(response.data));
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }

  Future<void> logout() async {
    final tokens = await _tokenStorage.read();
    try {
      if (tokens != null) {
        await _dio.post<void>(
          '/auth/logout',
          data: {'refresh_token': tokens.refreshToken},
          options: Options(extra: const {'skipRefresh': true}),
        );
      }
    } on DioException {
      // El cierre local debe completarse aun sin conectividad.
    } finally {
      await _tokenStorage.clear();
    }
  }

  static Map<String, dynamic> _envelope(Object? body) {
    if (body is Map<String, dynamic> && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw const AppException('El servidor devolvió una respuesta inválida.');
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    final access = data['access_token']?.toString();
    final refresh = data['refresh_token']?.toString();
    if (access == null || refresh == null) {
      throw const AppException('El servidor no entregó credenciales válidas.');
    }
    await _tokenStorage.save(
      SessionTokens(accessToken: access, refreshToken: refresh),
    );
  }
}
