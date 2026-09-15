import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/report_history_models.dart';

abstract class ReportHistoryDataSource {
  Future<ReportPage> getReports({required int page, int pageSize = 20});
  Future<ReportDetail> getReport(int reportId);
}

class ReportHistoryRepository implements ReportHistoryDataSource {
  ReportHistoryRepository(this._dio);
  final Dio _dio;

  @override
  Future<ReportPage> getReports({required int page, int pageSize = 20}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/reports',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      final body = response.data;
      if (body == null || body['data'] is! List || body['pagination'] is! Map) {
        throw const AppException('El servidor devolvió un historial inválido.');
      }
      final pagination = Map<String, dynamic>.from(body['pagination'] as Map);
      return ReportPage(
        reports: (body['data'] as List)
            .map(
              (item) => ReportSummary.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
        page: pagination['page'] as int,
        totalPages: pagination['total_pages'] as int,
      );
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }

  @override
  Future<ReportDetail> getReport(int reportId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/reports/$reportId',
      );
      final data = response.data?['data'];
      if (data is! Map) {
        throw const AppException('El servidor devolvió un reporte inválido.');
      }
      return ReportDetail.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }
}
