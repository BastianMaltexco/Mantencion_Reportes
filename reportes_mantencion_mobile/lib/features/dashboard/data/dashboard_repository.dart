import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';

class DashboardFilters {
  const DashboardFilters({
    this.dateFrom,
    this.dateTo,
    this.technicianId,
    this.areaId,
    this.sectionId,
    this.machineryId,
    this.recordType = 'all',
    this.serviceType,
  });
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int? technicianId;
  final int? areaId;
  final int? sectionId;
  final int? machineryId;
  final String recordType;
  final String? serviceType;
  bool get hasActive =>
      dateFrom != null ||
      dateTo != null ||
      technicianId != null ||
      areaId != null ||
      sectionId != null ||
      machineryId != null ||
      recordType != 'all' ||
      serviceType != null;
  DashboardFilters copyWith({
    DateTime? dateFrom,
    DateTime? dateTo,
    int? technicianId,
    int? areaId,
    int? sectionId,
    int? machineryId,
    String? recordType,
    String? serviceType,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    bool clearTechnician = false,
    bool clearArea = false,
    bool clearSection = false,
    bool clearMachinery = false,
    bool clearService = false,
  }) => DashboardFilters(
    dateFrom: clearDateFrom ? null : dateFrom ?? this.dateFrom,
    dateTo: clearDateTo ? null : dateTo ?? this.dateTo,
    technicianId: clearTechnician ? null : technicianId ?? this.technicianId,
    areaId: clearArea ? null : areaId ?? this.areaId,
    sectionId: clearSection ? null : sectionId ?? this.sectionId,
    machineryId: clearMachinery ? null : machineryId ?? this.machineryId,
    recordType: recordType ?? this.recordType,
    serviceType: clearService ? null : serviceType ?? this.serviceType,
  );
  Map<String, dynamic> query() => {
    if (dateFrom != null) 'date_from': dateFrom!.toIso8601String(),
    if (dateTo != null) 'date_to': dateTo!.toIso8601String(),
    if (technicianId != null) 'technician_id': technicianId,
    if (areaId != null) 'area_id': areaId,
    if (sectionId != null) 'section_id': sectionId,
    if (machineryId != null) 'machinery_id': machineryId,
    'record_type': recordType,
    if (serviceType != null) 'service_type': serviceType,
    'activity_page': 1,
    'activity_page_size': 30,
  };
}

class DashboardData {
  DashboardData(this.json);
  final Map<String, dynamic> json;
  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(json['summary'] as Map);
  List<Map<String, dynamic>> chart(String key) =>
      ((json['charts'] as Map)[key] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
  List<Map<String, dynamic>> get activity =>
      (json['activity'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
  List<Map<String, dynamic>> get technicians =>
      (json['technicians'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
}

class DashboardRepository {
  DashboardRepository(this._dio);
  final Dio _dio;
  Future<DashboardData> summary(DashboardFilters filters) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/dashboard/summary',
        queryParameters: filters.query(),
      );
      final data = response.data?['data'];
      if (data is! Map) {
        throw const AppException('El servidor devolvió un dashboard inválido.');
      }
      return DashboardData(Map<String, dynamic>.from(data));
    } on DioException catch (error) {
      throw AppException.fromDio(error);
    }
  }
}

final dashboardFiltersProvider =
    NotifierProvider<DashboardFiltersController, DashboardFilters>(
      DashboardFiltersController.new,
    );

class DashboardFiltersController extends Notifier<DashboardFilters> {
  @override
  DashboardFilters build() => const DashboardFilters();
  void update(DashboardFilters value) => state = value;
  void clear() => state = const DashboardFilters();
}

final dashboardRepositoryProvider = Provider(
  (ref) => DashboardRepository(ref.watch(dioProvider)),
);
final dashboardSummaryProvider = FutureProvider<DashboardData>(
  (ref) => ref
      .watch(dashboardRepositoryProvider)
      .summary(ref.watch(dashboardFiltersProvider)),
);
