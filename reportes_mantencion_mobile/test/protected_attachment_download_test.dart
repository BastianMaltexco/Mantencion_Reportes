import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_mantencion_mobile/core/config/app_config.dart';
import 'package:reportes_mantencion_mobile/core/network/api_client.dart';
import 'package:reportes_mantencion_mobile/core/network/private_api_path.dart';
import 'package:reportes_mantencion_mobile/core/network/secure_token_storage.dart';

void main() {
  test('normaliza la ruta privada del adjunto sin duplicar /api/v1', () {
    expect(
      privateApiPath(
        '/api/v1/attachments/42',
        'https://mantencion-reportes.onrender.com/api/v1',
      ),
      '/attachments/42',
    );
  });

  test('normaliza igualmente una fotografía privada de carga de petróleo', () {
    expect(
      privateApiPath(
        '/api/v1/fuel-loads/18/generators/1/images/water',
        'https://mantencion-reportes.onrender.com/api/v1',
      ),
      '/fuel-loads/18/generators/1/images/water',
    );
  });

  test('descarga bytes JPEG con JWT y renueva el token ante un 401', () async {
    final storage = _MemoryTokenStorage(
      const SessionTokens(
        accessToken: 'expired-access',
        refreshToken: 'refresh',
      ),
    );
    final protectedApi = _AttachmentAdapter();
    final refreshApi = _RefreshAdapter();
    final client = ApiClient(
      storage,
      () => fail('La renovación debió mantener la sesión activa.'),
      config: AppConfig.fromEnvironment(),
      dio: Dio(
        BaseOptions(baseUrl: 'https://mantencion-reportes.onrender.com/api/v1'),
      )..httpClientAdapter = protectedApi,
      refreshDio: Dio(
        BaseOptions(baseUrl: 'https://mantencion-reportes.onrender.com/api/v1'),
      )..httpClientAdapter = refreshApi,
    );

    final response = await client.dio.get<List<int>>(
      privateApiPath('/api/v1/attachments/42', client.dio.options.baseUrl),
      options: Options(responseType: ResponseType.bytes),
    );

    expect(response.statusCode, 200);
    expect(response.headers.value(Headers.contentTypeHeader), 'image/jpeg');
    expect(response.data, <int>[0xff, 0xd8, 0xff, 0xd9]);
    expect(protectedApi.requestUris, [
      'https://mantencion-reportes.onrender.com/api/v1/attachments/42',
      'https://mantencion-reportes.onrender.com/api/v1/attachments/42',
    ]);
    expect(protectedApi.authorizationHeaders, [
      'Bearer expired-access',
      'Bearer renewed-access',
    ]);
    expect(refreshApi.requestPaths, ['/auth/refresh']);
    expect(storage.tokens?.accessToken, 'renewed-access');
  });
}

class _MemoryTokenStorage implements TokenStorage {
  _MemoryTokenStorage(this.tokens);
  SessionTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<SessionTokens?> read() async => tokens;

  @override
  Future<void> save(SessionTokens value) async => tokens = value;
}

class _AttachmentAdapter implements HttpClientAdapter {
  final requestUris = <String>[];
  final authorizationHeaders = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestUris.add(options.uri.toString());
    authorizationHeaders.add(
      options.headers['Authorization']?.toString() ?? '',
    );
    if (options.headers['Authorization'] == 'Bearer expired-access') {
      return ResponseBody.fromString(
        '{"error":{"code":"token_expired"}}',
        401,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromBytes(
      const [0xff, 0xd8, 0xff, 0xd9],
      200,
      headers: {
        Headers.contentTypeHeader: ['image/jpeg'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RefreshAdapter implements HttpClientAdapter {
  final requestPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestPaths.add(options.path);
    return ResponseBody.fromBytes(
      utf8.encode(
        '{"data":{"access_token":"renewed-access","refresh_token":"renewed-refresh"}}',
      ),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
