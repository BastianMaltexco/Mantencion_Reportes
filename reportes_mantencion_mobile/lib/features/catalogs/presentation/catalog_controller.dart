import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_item.dart';

class CatalogState {
  const CatalogState({
    this.areas = const [],
    this.sections = const [],
    this.machineries = const [],
    this.areaId,
    this.sectionId,
    this.machineryId,
    this.isLoadingSections = false,
    this.isLoadingMachineries = false,
  });

  final List<Area> areas;
  final List<Section> sections;
  final List<Machinery> machineries;
  final int? areaId;
  final int? sectionId;
  final int? machineryId;
  final bool isLoadingSections;
  final bool isLoadingMachineries;

  CatalogState copyWith({
    List<Area>? areas,
    List<Section>? sections,
    List<Machinery>? machineries,
    int? areaId,
    int? sectionId,
    int? machineryId,
    bool? isLoadingSections,
    bool? isLoadingMachineries,
    bool clearArea = false,
    bool clearSection = false,
    bool clearMachinery = false,
  }) => CatalogState(
    areas: areas ?? this.areas,
    sections: sections ?? this.sections,
    machineries: machineries ?? this.machineries,
    areaId: clearArea ? null : (areaId ?? this.areaId),
    sectionId: clearSection ? null : (sectionId ?? this.sectionId),
    machineryId: clearMachinery ? null : (machineryId ?? this.machineryId),
    isLoadingSections: isLoadingSections ?? this.isLoadingSections,
    isLoadingMachineries: isLoadingMachineries ?? this.isLoadingMachineries,
  );
}

final catalogRepositoryProvider = Provider<CatalogDataSource>(
  (ref) => CatalogRepository(ref.watch(dioProvider)),
);
final catalogControllerProvider =
    AsyncNotifierProvider<CatalogController, CatalogState>(
      CatalogController.new,
    );

class CatalogController extends AsyncNotifier<CatalogState> {
  CatalogState _current = const CatalogState();

  @override
  Future<CatalogState> build() async {
    final areas = await ref.read(catalogRepositoryProvider).getAreas();
    _current = CatalogState(areas: areas);
    return _current;
  }

  Future<void> selectArea(int? areaId) async {
    // Primero se limpia el estado dependiente y se repinta. Nunca se conserva
    // una Section/Machinery elegida mientras llega el catálogo nuevo.
    _current = _current.copyWith(
      areaId: areaId,
      sections: const [],
      machineries: const [],
      clearArea: areaId == null,
      clearSection: true,
      clearMachinery: true,
      isLoadingSections: areaId != null,
      isLoadingMachineries: false,
    );
    state = AsyncData(_current);
    if (areaId == null) return;

    try {
      final sections = await ref
          .read(catalogRepositoryProvider)
          .getSections(areaId);
      // Ignora respuestas tardías si el usuario ya cambió de área.
      if (_current.areaId != areaId) return;
      _current = _current.copyWith(
        sections: sections,
        isLoadingSections: false,
      );
      state = AsyncData(_current);
    } catch (error, stackTrace) {
      if (_current.areaId == areaId) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  Future<void> selectSection(int? sectionId) async {
    // Primero se limpia maquinaria, antes de solicitar las nuevas opciones.
    _current = _current.copyWith(
      sectionId: sectionId,
      machineries: const [],
      clearSection: sectionId == null,
      clearMachinery: true,
      isLoadingMachineries: sectionId != null,
    );
    state = AsyncData(_current);
    if (sectionId == null) return;

    try {
      final machinery = await ref
          .read(catalogRepositoryProvider)
          .getMachineries(sectionId);
      // Ignora respuestas tardías si el usuario ya eligió otra sección.
      if (_current.sectionId != sectionId) return;
      _current = _current.copyWith(
        machineries: machinery,
        isLoadingMachineries: false,
      );
      state = AsyncData(_current);
    } catch (error, stackTrace) {
      if (_current.sectionId == sectionId) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  void selectMachinery(int? machineryId) {
    _current = _current.copyWith(
      machineryId: machineryId,
      clearMachinery: machineryId == null,
    );
    state = AsyncData(_current);
  }
}
