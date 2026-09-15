import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/catalog_item.dart';

abstract class CatalogDataSource {
  Future<List<Area>> getAreas();
  Future<List<Section>> getSections(int areaId);
  Future<List<Machinery>> getMachineries(int sectionId);
}

class CatalogRepository implements CatalogDataSource {
  CatalogRepository(this._dio);
  final Dio _dio;

  @override
  Future<List<Area>> getAreas() =>
      _getList('/areas', Area.fromJson, (item) => item.id);

  @override
  Future<List<Section>> getSections(int areaId) => _getList(
    '/sections',
    Section.fromJson,
    (item) => item.id,
    {'area_id': areaId},
  );

  @override
  Future<List<Machinery>> getMachineries(int sectionId) => _getList(
    '/machineries',
    Machinery.fromJson,
    (item) => item.id,
    {'section_id': sectionId},
  );

  Future<List<T>> _getList<T>(
    String path,
    T Function(Map<String, dynamic>) mapper,
    int Function(T) idOf, [
    Map<String, dynamic>? query,
  ]) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: query,
      );
      final body = response.data;
      if (body == null || body['data'] is! List) {
        throw const AppException('El servidor devolvió un catálogo inválido.');
      }
      final items = (body['data'] as List)
          .map((item) => mapper(Map<String, dynamic>.from(item as Map)))
          .toList();
      validateUniqueCatalogIds(items, idOf, path);
      return items;
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }
}

/// Un ID repetido indica un problema de integridad en la API o la base. No se
/// elimina ni se oculta: el usuario recibe un error claro y puede informarlo.
void validateUniqueCatalogIds<T>(
  List<T> items,
  int Function(T) idOf,
  String endpoint,
) {
  final seen = <int>{};
  final duplicates = <int>{};
  for (final item in items) {
    final id = idOf(item);
    if (!seen.add(id)) duplicates.add(id);
  }
  if (duplicates.isNotEmpty) {
    throw AppException(
      'La API devolvió IDs duplicados en $endpoint: ${duplicates.join(', ')}.',
      code: 'duplicate_catalog_id',
      details: {'endpoint': endpoint, 'duplicate_ids': duplicates.toList()},
    );
  }
}
