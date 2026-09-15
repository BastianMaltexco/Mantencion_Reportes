import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reportes_mantencion_mobile/features/fuel_loads/data/fuel_load_repository.dart';
import 'package:reportes_mantencion_mobile/features/fuel_loads/domain/fuel_load.dart';
import 'package:reportes_mantencion_mobile/features/fuel_loads/presentation/fuel_load_controller.dart';
import 'package:reportes_mantencion_mobile/features/fuel_loads/presentation/fuel_load_history_controller.dart';

void main() {
  test(
    'valida litros estrictamente menores a 750 y las cuatro fotografías',
    () {
      final invalid = _input(liters1: '750');
      expect(
        invalid.validate(imageKeys: const {'water_1', 'oil_1', 'water_2'}),
        containsAll([
          contains('0 a 749,99'),
          contains('Generador 2: adjunte fotografía de nivel de aceite'),
        ]),
      );

      final valid = _input(liters1: '749.99');
      expect(
        valid.validate(
          imageKeys: const {'water_1', 'oil_1', 'water_2', 'oil_2'},
        ),
        isEmpty,
      );
      expect(valid.toJson()['generators'], hasLength(2));
    },
  );

  test('conserva las cuatro rutas privadas de fotografías al leer detalle', () {
    final detail = FuelLoadDetail.fromJson({
      'id': 18,
      'loaded_at': '2026-09-15T12:00:00Z',
      'created_at': '2026-09-15T12:01:00Z',
      'technician': {'full_name': 'Técnico'},
      'generators': [
        {
          'number': 1,
          'liters': 749,
          'hourmeter': 35.5,
          'water_image_path': '/api/v1/fuel-loads/18/generators/1/images/water',
          'oil_image_path': '/api/v1/fuel-loads/18/generators/1/images/oil',
        },
      ],
    });
    expect(detail.generators.single.liters, 749);
    expect(
      detail.generators.single.waterImagePath,
      '/api/v1/fuel-loads/18/generators/1/images/water',
    );
  });

  test(
    'pagina historial de cargas sin filtrar permisos en el cliente',
    () async {
      final repository = _FakeFuelRepository();
      final container = ProviderContainer(
        overrides: [fuelLoadRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container.read(fuelLoadHistoryProvider.future);
      await container.read(fuelLoadHistoryProvider.notifier).loadMore();

      final state = container.read(fuelLoadHistoryProvider).requireValue;
      expect(state.loads.map((load) => load.id), [1, 2]);
      expect(repository.requestedPages, [1, 2]);
    },
  );
}

FuelLoadInput _input({required String liters1}) => FuelLoadInput(
  loadedAt: DateTime(2026, 9, 15, 12),
  observations: '',
  generators: [
    FuelGeneratorInput(number: 1, liters: liters1, hourmeter: '10'),
    const FuelGeneratorInput(number: 2, liters: '15', hourmeter: '20'),
  ],
);

class _FakeFuelRepository implements FuelLoadDataSource {
  final requestedPages = <int>[];

  @override
  Future<int> createFuelLoad(
    FuelLoadInput load, {
    required Map<String, XFile> images,
    void Function(int sent, int total)? onSendProgress,
  }) => throw UnimplementedError();

  @override
  Future<FuelLoadDetail> getFuelLoad(int loadId) => throw UnimplementedError();

  @override
  Future<FuelLoadPage> getFuelLoads({
    required int page,
    int pageSize = 20,
  }) async {
    requestedPages.add(page);
    return FuelLoadPage(
      loads: [
        FuelLoadSummary(
          id: page,
          loadedAt: DateTime(2026, 9, page),
          createdAt: DateTime(2026, 9, page),
          technicianName: 'Técnico',
        ),
      ],
      page: page,
      totalPages: 2,
    );
  }
}
