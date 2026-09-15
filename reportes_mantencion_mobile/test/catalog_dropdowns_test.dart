import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_mantencion_mobile/core/errors/app_exception.dart';
import 'package:reportes_mantencion_mobile/features/catalogs/data/catalog_repository.dart';
import 'package:reportes_mantencion_mobile/features/catalogs/domain/catalog_item.dart';
import 'package:reportes_mantencion_mobile/features/catalogs/presentation/catalog_controller.dart';
import 'package:reportes_mantencion_mobile/features/catalogs/presentation/catalogs_page.dart';

void main() {
  group('catálogos encadenados', () {
    test(
      'al cambiar área limpia sección y maquinaria antes de recibir opciones',
      () async {
        final repository = _FakeCatalogRepository();
        final container = ProviderContainer(
          overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        await container.read(catalogControllerProvider.future);

        final controller = container.read(catalogControllerProvider.notifier);
        await controller.selectArea(1);
        await controller.selectSection(11);
        controller.selectMachinery(111);

        final pending = controller.selectArea(2);
        final cleared = container.read(catalogControllerProvider).requireValue;
        expect(cleared.areaId, 2);
        expect(cleared.sectionId, isNull);
        expect(cleared.machineryId, isNull);
        expect(cleared.sections, isEmpty);
        expect(cleared.machineries, isEmpty);
        expect(cleared.isLoadingSections, isTrue);

        repository.sectionsForArea2.complete([
          const Section(id: 21, areaId: 2, name: 'Nueva sección'),
        ]);
        await pending;
        final loaded = container.read(catalogControllerProvider).requireValue;
        expect(loaded.sections.single.id, 21);
        expect(loaded.sectionId, isNull);
      },
    );

    test(
      'al cambiar sección limpia maquinaria y descarta respuesta anterior',
      () async {
        final repository = _FakeCatalogRepository();
        final container = ProviderContainer(
          overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        await container.read(catalogControllerProvider.future);

        final controller = container.read(catalogControllerProvider.notifier);
        await controller.selectArea(1);
        await controller.selectSection(11);
        controller.selectMachinery(111);

        final pending = controller.selectSection(12);
        final cleared = container.read(catalogControllerProvider).requireValue;
        expect(cleared.sectionId, 12);
        expect(cleared.machineryId, isNull);
        expect(cleared.machineries, isEmpty);
        expect(cleared.isLoadingMachineries, isTrue);

        repository.machineryForSection12.complete([
          const Machinery(id: 121, sectionId: 12, name: 'Nueva máquina'),
        ]);
        await pending;
        expect(
          container
              .read(catalogControllerProvider)
              .requireValue
              .machineries
              .single
              .id,
          121,
        );
      },
    );

    testWidgets(
      'los dropdowns reconstruidos conservan únicamente valores int válidos',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _FakeCatalogRepository();
        final container = ProviderContainer(
          overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        await container.read(catalogControllerProvider.future);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: CatalogsPage()),
          ),
        );

        final controller = container.read(catalogControllerProvider.notifier);
        await controller.selectArea(1);
        await controller.selectSection(11);
        controller.selectMachinery(111);
        await tester.pump();
        expect(tester.takeException(), isNull);

        repository.sectionsForArea2.complete([
          const Section(id: 21, areaId: 2, name: 'Nueva sección'),
        ]);
        await controller.selectArea(2);
        await tester.pump();
        expect(tester.takeException(), isNull);

        final fields = tester
            .widgetList<DropdownButtonFormField<int>>(
              find.byType(DropdownButtonFormField<int>),
            )
            .toList();
        expect(fields, hasLength(3));
        expect(fields[0].initialValue, 2);
        expect(fields[0].initialValue, isA<int>());
        expect(fields[1].initialValue, isNull);
        expect(fields[2].initialValue, isNull);
      },
    );

    test('IDs duplicados de la API se reportan, no se ocultan', () {
      expect(
        () => validateUniqueCatalogIds(
          [const Area(id: 7, name: 'A'), const Area(id: 7, name: 'B')],
          (area) => area.id,
          '/areas',
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'duplicate_catalog_id',
          ),
        ),
      );
    });
  });
}

class _FakeCatalogRepository implements CatalogDataSource {
  final sectionsForArea2 = Completer<List<Section>>();
  final machineryForSection12 = Completer<List<Machinery>>();

  @override
  Future<List<Area>> getAreas() async => const [
    Area(
      id: 1,
      name: 'PLANTA GENERAL CON DENOMINACIÓN EXTENSA PARA PRUEBA MÓVIL',
    ),
    Area(id: 2, name: 'OTRA ÁREA CON DENOMINACIÓN EXTENSA PARA PRUEBA MÓVIL'),
  ];

  @override
  Future<List<Section>> getSections(int areaId) {
    if (areaId == 2) return sectionsForArea2.future;
    return Future.value(const [
      Section(
        id: 11,
        areaId: 1,
        name: 'Sección uno con denominación muy extensa para prueba móvil',
      ),
      Section(
        id: 12,
        areaId: 1,
        name: 'Sección dos con denominación muy extensa para prueba móvil',
      ),
    ]);
  }

  @override
  Future<List<Machinery>> getMachineries(int sectionId) {
    if (sectionId == 12) return machineryForSection12.future;
    return Future.value(const [
      Machinery(
        id: 111,
        sectionId: 11,
        name: 'TINA - 1 · Nombre extenso para comprobar el ajuste móvil',
      ),
    ]);
  }
}
