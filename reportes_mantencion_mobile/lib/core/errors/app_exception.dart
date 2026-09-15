import 'package:dio/dio.dart';

class AppException implements Exception {
  const AppException(this.message, {this.code = 'unknown_error', this.details});

  factory AppException.fromDio(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic> && body['error'] is Map) {
      final apiError = Map<String, dynamic>.from(body['error'] as Map);
      return AppException(
        apiError['message']?.toString() ?? 'Ocurrió un error inesperado.',
        code: apiError['code']?.toString() ?? 'api_error',
        details: apiError['details'] is Map
            ? Map<String, dynamic>.from(apiError['details'] as Map)
            : null,
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return const AppException(
        'No fue posible conectarse al servicio. Revisa tu conexión e inténtalo nuevamente.',
        code: 'network_error',
      );
    }
    return const AppException(
      'Ocurrió un error inesperado. Inténtalo nuevamente.',
    );
  }

  final String message;
  final String code;
  final Map<String, dynamic>? details;

  @override
  String toString() => message;
}
