import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'secure_token_storage.dart';

/// Cliente único para toda comunicación HTTPS con Flask.
/// Ante un 401 renueva el access token una sola vez y repite la solicitud.
class ApiClient {
  ApiClient(
    this._tokenStorage,
    this._onSessionExpired, {
    required AppConfig config,
    Dio? dio,
    Dio? refreshDio,
  }) : _refreshDio =
           refreshDio ?? Dio(BaseOptions(baseUrl: config.apiBaseUrl)) {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: config.apiBaseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
            headers: const {'Accept': 'application/json'},
          ),
        );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['skipAuth'] != true) {
            final tokens = await _tokenStorage.read();
            if (tokens != null) {
              options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          final canRetry =
              error.response?.statusCode == 401 &&
              request.extra['skipRefresh'] != true &&
              request.extra['retried'] != true;
          if (!canRetry || !await _refreshAccessToken()) {
            handler.next(error);
            return;
          }
          try {
            request.extra['retried'] = true;
            final response = await _dio.fetch<dynamic>(request);
            handler.resolve(response);
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
        },
      ),
    );
  }

  late final Dio _dio;
  final Dio _refreshDio;
  final TokenStorage _tokenStorage;
  final void Function() _onSessionExpired;
  Future<bool>? _refreshOperation;

  Dio get dio => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) => _dio.get<T>(path, queryParameters: queryParameters);

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    bool skipAuth = false,
  }) => _dio.post<T>(
    path,
    data: data,
    options: Options(
      extra: {
        if (skipAuth) 'skipAuth': true,
        if (skipAuth) 'skipRefresh': true,
      },
    ),
  );

  Future<bool> _refreshAccessToken() {
    return _refreshOperation ??= _performRefresh().whenComplete(() {
      _refreshOperation = null;
    });
  }

  Future<bool> _performRefresh() async {
    final tokens = await _tokenStorage.read();
    if (tokens == null) return false;
    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': tokens.refreshToken},
      );
      final data = _data(response.data);
      final access = data['access_token']?.toString();
      final refresh = data['refresh_token']?.toString();
      if (access == null || refresh == null) throw const FormatException();
      await _tokenStorage.save(
        SessionTokens(accessToken: access, refreshToken: refresh),
      );
      return true;
    } catch (_) {
      await _tokenStorage.clear();
      _onSessionExpired();
      return false;
    }
  }

  static Map<String, dynamic> _data(Object? body) {
    if (body is Map<String, dynamic> && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw const FormatException('Respuesta API inválida.');
  }
}
