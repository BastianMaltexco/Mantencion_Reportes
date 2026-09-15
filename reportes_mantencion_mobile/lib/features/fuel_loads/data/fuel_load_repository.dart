import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/fuel_load.dart';

abstract class FuelLoadDataSource {
  Future<int> createFuelLoad(
    FuelLoadInput load, {
    required Map<String, XFile> images,
    void Function(int sent, int total)? onSendProgress,
  });
  Future<FuelLoadPage> getFuelLoads({required int page, int pageSize = 20});
  Future<FuelLoadDetail> getFuelLoad(int loadId);
}

class FuelLoadRepository implements FuelLoadDataSource {
  FuelLoadRepository(this._dio);
  final Dio _dio;

  @override
  Future<int> createFuelLoad(
    FuelLoadInput load, {
    required Map<String, XFile> images,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final formData = FormData.fromMap({'payload': jsonEncode(load.toJson())});
      for (final entry in images.entries) {
        formData.files.add(MapEntry(entry.key, await _imagePart(entry.value)));
      }
      final response = await _dio.post<Map<String, dynamic>>(
        '/fuel-loads',
        data: formData,
        onSendProgress: onSendProgress,
      );
      final data = response.data?['data'];
      if (data is! Map || data['id'] is! int) {
        throw const AppException('El servidor devolvió una carga inválida.');
      }
      return data['id'] as int;
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }

  @override
  Future<FuelLoadPage> getFuelLoads({
    required int page,
    int pageSize = 20,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/fuel-loads',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      final body = response.data;
      if (body == null || body['data'] is! List || body['pagination'] is! Map) {
        throw const AppException('El servidor devolvió un historial inválido.');
      }
      final pagination = Map<String, dynamic>.from(body['pagination'] as Map);
      return FuelLoadPage(
        loads: (body['data'] as List)
            .map(
              (item) => FuelLoadSummary.fromJson(
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
  Future<FuelLoadDetail> getFuelLoad(int loadId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/fuel-loads/$loadId',
      );
      final data = response.data?['data'];
      if (data is! Map) {
        throw const AppException('El servidor devolvió una carga inválida.');
      }
      return FuelLoadDetail.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }

  Future<MultipartFile> _imagePart(XFile file) async {
    final filename = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final lower = filename.toLowerCase();
    if (!(lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png'))) {
      throw const AppException(
        'Las fotografías deben estar en formato JPG o PNG.',
        code: 'invalid_image_format',
      );
    }
    return MultipartFile.fromBytes(
      await file.readAsBytes(),
      filename: filename,
      contentType: MediaType.parse(
        lower.endsWith('.png') ? 'image/png' : 'image/jpeg',
      ),
    );
  }
}
