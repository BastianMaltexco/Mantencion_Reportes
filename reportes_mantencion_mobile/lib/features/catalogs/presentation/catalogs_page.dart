import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog_controller.dart';

/// Consulta encadenada de catálogos reales. Los Dropdowns usan IDs enteros,
/// nunca objetos de la API que puedan cambiar de instancia al reconstruirse.
class CatalogsPage extends ConsumerWidget {
  const CatalogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogs = ref.watch(catalogControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Áreas y maquinarias')),
      body: catalogs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(catalogControllerProvider),
        ),
        data: (state) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Catálogos de terreno',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('Selecciona un área, una sección y una maquinaria.'),
            const SizedBox(height: 24),
            _IdSelector(
              key: const ValueKey('area-selector'),
              label: 'Área',
              selectedId: _validSelectedId(
                state.areas.map((item) => item.id),
                state.areaId,
              ),
              items: state.areas
                  .map((item) => _IdOption(item.id, item.name))
                  .toList(),
              onChanged: (id) =>
                  ref.read(catalogControllerProvider.notifier).selectArea(id),
            ),
            const SizedBox(height: 16),
            _IdSelector(
              // Fuerza que el FormField pierda cualquier estado previo cuando
              // cambia su nivel padre, incluso antes de terminar la solicitud.
              key: ValueKey('section-selector-${state.areaId}'),
              label: 'Sección',
              selectedId: _validSelectedId(
                state.sections.map((item) => item.id),
                state.sectionId,
              ),
              items: state.sections
                  .map((item) => _IdOption(item.id, item.name))
                  .toList(),
              enabled: state.areaId != null && !state.isLoadingSections,
              isLoading: state.isLoadingSections,
              onChanged: (id) => ref
                  .read(catalogControllerProvider.notifier)
                  .selectSection(id),
            ),
            const SizedBox(height: 16),
            _IdSelector(
              key: ValueKey(
                'machinery-selector-${state.areaId}-${state.sectionId}',
              ),
              label: 'Maquinaria',
              selectedId: _validSelectedId(
                state.machineries.map((item) => item.id),
                state.machineryId,
              ),
              items: state.machineries
                  .map((item) => _IdOption(item.id, item.name))
                  .toList(),
              enabled: state.sectionId != null && !state.isLoadingMachineries,
              isLoading: state.isLoadingMachineries,
              onChanged: (id) => ref
                  .read(catalogControllerProvider.notifier)
                  .selectMachinery(id),
            ),
            if (state.machineryId != null) ...[
              const SizedBox(height: 28),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'La selección está lista para reutilizarse en el formulario de reporte.',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Defensa adicional para el FormField. El repositorio ya rechaza IDs
  /// duplicados; esta comprobación evita valores fuera de la lista durante una
  /// transición de estado asíncrona.
  int? _validSelectedId(Iterable<int> ids, int? selectedId) {
    if (selectedId == null) return null;
    final matches = ids.where((id) => id == selectedId).length;
    return matches == 1 ? selectedId : null;
  }
}

class _IdOption {
  const _IdOption(this.id, this.label);
  final int id;
  final String label;
}

class _IdSelector extends StatelessWidget {
  const _IdSelector({
    super.key,
    required this.label,
    required this.selectedId,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.isLoading = false,
  });

  final String label;
  final int? selectedId;
  final List<_IdOption> items;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    isExpanded: true,
    initialValue: selectedId,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: isLoading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
    ),
    hint: Text(
      isLoading
          ? 'Cargando opciones…'
          : enabled
          ? items.isEmpty
                ? 'No hay opciones disponibles'
                : 'Selecciona una opción'
          : 'Selecciona antes el nivel anterior',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    ),
    selectedItemBuilder: (context) => items
        .map(
          (item) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    items: items
        .map(
          (item) => DropdownMenuItem<int>(
            value: item.id,
            child: Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: enabled && !isLoading && items.isNotEmpty ? onChanged : null,
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
