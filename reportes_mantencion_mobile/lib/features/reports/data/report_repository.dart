import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/maintenance_report.dart';

abstract class ReportDataSource {
  Future<int> createMaintenanceReport(
    MaintenanceReportInput report, {
    required Map<String, XFile> evidence,
  });
}

class ReportRepository implements ReportDataSource {
  ReportRepository(this._dio);
  final Dio _dio;

  @override
  Future<int> createMaintenanceReport(
    MaintenanceReportInput report, {
    required Map<String, XFile> evidence,
  }) async {
    try {
      final formData = FormData.fromMap({
        'payload': jsonEncode(report.toJson()),
      });
      for (final entry in evidence.entries) {
        formData.files.add(
          MapEntry('evidence_${entry.key}', await _imagePart(entry.value)),
        );
      }
      final response = await _dio.post<Map<String, dynamic>>(
        '/reports',
        data: formData,
      );
      final data = response.data?['data'];
      if (data is! Map || data['id'] is! int) {
        throw const AppException(
          'El servidor devolvió una respuesta inválida al crear el reporte.',
        );
      }
      return data['id'] as int;
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }

  Future<MultipartFile> _imagePart(XFile file) async {
    final filename = _safeImageName(file.name);
    if (filename.isEmpty) {
      throw const AppException(
        'La evidencia debe estar en formato JPG o PNG.',
        code: 'invalid_image_format',
      );
    }
    final mime = filename.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    return MultipartFile.fromBytes(
      await file.readAsBytes(),
      filename: filename,
      contentType: MediaType.parse(mime),
    );
  }

  String _safeImageName(String original) {
    final normalized = original.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (normalized.toLowerCase().endsWith('.jpg') ||
        normalized.toLowerCase().endsWith('.jpeg') ||
        normalized.toLowerCase().endsWith('.png')) {
      return normalized;
    }
    return '';
  }
}
