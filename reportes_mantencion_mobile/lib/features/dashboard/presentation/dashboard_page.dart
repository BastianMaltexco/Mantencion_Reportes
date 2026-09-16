import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../catalogs/domain/catalog_item.dart';
import '../../catalogs/presentation/catalog_controller.dart';
import '../../reports/domain/maintenance_report.dart';
import '../data/dashboard_repository.dart';

final _areasProvider = FutureProvider<List<Area>>(
  (ref) => ref.watch(catalogRepositoryProvider).getAreas(),
);
final _sectionsProvider = FutureProvider.family<List<Section>, int>(
  (ref, areaId) => ref.watch(catalogRepositoryProvider).getSections(areaId),
);
final _machinesProvider = FutureProvider.family<List<Machinery>, int>(
  (ref, sectionId) =>
      ref.watch(catalogRepositoryProvider).getMachineries(sectionId),
);

class MobileDashboardPage extends ConsumerWidget {
  const MobileDashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardSummaryProvider);
    final filters = ref.watch(dashboardFiltersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: SafeArea(
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _DashboardError(
            message: error.toString(),
            onRetry: () => ref.invalidate(dashboardSummaryProvider),
          ),
          data: (dashboard) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(dashboardSummaryProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Filters(data: dashboard, filters: filters),
                const SizedBox(height: 16),
                if (dashboard.summary['total_records'] == 0)
                  const _EmptyDashboard()
                else ...[
                  _SummaryGrid(summary: dashboard.summary),
                  const SizedBox(height: 16),
                  _ChartCard(
                    title: 'Registros por día',
                    items: dashboard.chart('records_by_day'),
                    labelKey: 'date',
                  ),
                  _ChartCard(
                    title: 'Distribución por área',
                    items: dashboard.chart('areas'),
                  ),
                  _ChartCard(
                    title: 'Maquinarias con más intervenciones',
                    items: dashboard.chart('machineries'),
                  ),
                  _ChartCard(
                    title: 'Tipo de servicio',
                    items: dashboard.chart('service_types'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Actividad reciente',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ...dashboard.activity.map(
                    (item) => _ActivityTile(item: item),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.data, required this.filters});
  final DashboardData data;
  final DashboardFilters filters;
  void _set(WidgetRef ref, DashboardFilters value) =>
      ref.read(dashboardFiltersProvider.notifier).update(value);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(_areasProvider);
    final sections = filters.areaId == null
        ? const AsyncData<List<Section>>([])
        : ref.watch(_sectionsProvider(filters.areaId!));
    final machines = filters.sectionId == null
        ? const AsyncData<List<Machinery>>([])
        : ref.watch(_machinesProvider(filters.sectionId!));
    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: _DateButton(
              label: 'Desde',
              value: filters.dateFrom,
              onPick: (v) => _set(ref, filters.copyWith(dateFrom: v)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _DateButton(
              label: 'Hasta',
              value: filters.dateTo,
              onPick: (v) => _set(ref, filters.copyWith(dateTo: v)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: filters.recordType,
        decoration: const InputDecoration(labelText: 'Tipo de registro'),
        items: const [
          DropdownMenuItem(value: 'all', child: Text('Todos')),
          DropdownMenuItem(value: 'maintenance', child: Text('Mantención')),
          DropdownMenuItem(value: 'fuel', child: Text('Carga de petróleo')),
        ],
        onChanged: (v) => _set(
          ref,
          filters.copyWith(recordType: v ?? 'all', clearService: true),
        ),
      ),
    ];
    if (data.technicians.length > 1) {
      children.addAll([
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: filters.technicianId,
          decoration: const InputDecoration(labelText: 'Técnico'),
          hint: const Text('Todos'),
          items: data.technicians
              .map(
                (u) => DropdownMenuItem(
                  value: u['id'] as int,
                  child: Text(
                    u['full_name'].toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => _set(
            ref,
            filters.copyWith(technicianId: v, clearTechnician: v == null),
          ),
        ),
      ]);
    }
    if (filters.recordType != 'fuel') {
      children.addAll([
        const SizedBox(height: 12),
        areas.when(
          data: (items) => _Dropdown<Area>(
            label: 'Área',
            value: filters.areaId,
            items: items,
            id: (x) => x.id,
            name: (x) => x.name,
            onChanged: (v) => _set(
              ref,
              filters.copyWith(
                areaId: v,
                clearArea: v == null,
                clearSection: true,
                clearMachinery: true,
              ),
            ),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('No fue posible cargar áreas.'),
        ),
        const SizedBox(height: 12),
        sections.when(
          data: (items) => _Dropdown<Section>(
            label: 'Sección',
            value: filters.sectionId,
            items: items,
            id: (x) => x.id,
            name: (x) => x.name,
            onChanged: (v) => _set(
              ref,
              filters.copyWith(
                sectionId: v,
                clearSection: v == null,
                clearMachinery: true,
              ),
            ),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('No fue posible cargar secciones.'),
        ),
        const SizedBox(height: 12),
        machines.when(
          data: (items) => _Dropdown<Machinery>(
            label: 'Maquinaria',
            value: filters.machineryId,
            items: items,
            id: (x) => x.id,
            name: (x) => x.name,
            onChanged: (v) => _set(
              ref,
              filters.copyWith(machineryId: v, clearMachinery: v == null),
            ),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('No fue posible cargar maquinarias.'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: filters.serviceType,
          decoration: const InputDecoration(labelText: 'Tipo de mantención'),
          hint: const Text('Todos'),
          items: serviceTypes
              .map(
                (x) => DropdownMenuItem(
                  value: x,
                  child: Text(x, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) => _set(
            ref,
            filters.copyWith(serviceType: v, clearService: v == null),
          ),
        ),
      ]);
    }
    children.add(
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => ref.read(dashboardFiltersProvider.notifier).clear(),
          icon: const Icon(Icons.filter_alt_off_outlined),
          label: const Text('Limpiar filtros'),
        ),
      ),
    );
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Badge(
          isLabelVisible: filters.hasActive,
          child: const Icon(Icons.filter_list_outlined),
        ),
        title: const Text('Filtros'),
        subtitle: Text(
          filters.hasActive ? 'Filtros activos' : 'Sin filtros aplicados',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPick,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () async {
      final result = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (result != null) onPick(result);
    },
    child: Text(
      value == null
          ? label
          : '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}',
    ),
  );
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.id,
    required this.name,
    required this.onChanged,
  });
  final String label;
  final int? value;
  final List<T> items;
  final int Function(T) id;
  final String Function(T) name;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    isExpanded: true,
    initialValue:
        value != null && items.where((x) => id(x) == value).length == 1
        ? value
        : null,
    decoration: InputDecoration(labelText: label),
    hint: const Text('Todos'),
    items: items
        .map(
          (x) => DropdownMenuItem(
            value: id(x),
            child: Text(name(x), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: items.isEmpty ? null : onChanged,
  );
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});
  final Map<String, dynamic> summary;
  @override
  Widget build(BuildContext context) {
    const cards = [
      ['Registros', 'total_records'],
      ['Mantención', 'maintenance_reports'],
      ['Petróleo', 'fuel_loads'],
      ['Días activos', 'activity_days'],
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.65,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: cards
          .map(
            (item) => Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item[0], maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(
                      '${summary[item[1]] ?? 0}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.items,
    this.labelKey = 'name',
  });
  final String title;
  final List<Map<String, dynamic>> items;
  final String labelKey;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final max = items
        .map((x) => (x['count'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...items
                .take(6)
                .map(
                  (x) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            x[labelKey].toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: LinearProgressIndicator(
                            value: (x['count'] as num).toDouble() / max,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${x['count']}'),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(
        item['record_type'] == 'fuel'
            ? Icons.local_gas_station_outlined
            : Icons.build_outlined,
      ),
      title: Text(
        item['title'].toString(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item['service_type']} · ${item['technician_name']}\n${item['area_name'] ?? 'Sin maquinaria'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
        item['record_type'] == 'fuel'
            ? '/fuel-loads/${item['id']}'
            : '/reports/${item['id']}',
      ),
    ),
  );
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(48),
    child: Center(
      child: Text('No hay registros para los filtros seleccionados.'),
    ),
  );
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});
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
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
