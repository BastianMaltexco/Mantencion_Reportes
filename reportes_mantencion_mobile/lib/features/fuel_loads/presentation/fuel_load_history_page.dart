import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/fuel_load.dart';
import 'fuel_load_history_controller.dart';

class FuelLoadHistoryPage extends ConsumerWidget {
  const FuelLoadHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(fuelLoadHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de cargas')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(fuelLoadHistoryProvider),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: () => ref.read(fuelLoadHistoryProvider.notifier).refresh(),
          child: state.loads.isEmpty
              ? ListView(children: const [_EmptyState()])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: state.loads.length + (state.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == state.loads.length) {
                      if (!state.isLoadingMore) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => ref
                              .read(fuelLoadHistoryProvider.notifier)
                              .loadMore(),
                        );
                      }
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _FuelLoadTile(load: state.loads[index]);
                  },
                ),
        ),
      ),
    );
  }
}

class _FuelLoadTile extends StatelessWidget {
  const _FuelLoadTile({required this.load});
  final FuelLoadSummary load;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.local_gas_station_outlined),
      ),
      title: Text('Carga #${load.id}'),
      subtitle: Text(
        '${MaterialLocalizations.of(context).formatShortDate(load.loadedAt)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(load.loadedAt))}\n${load.technicianName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/fuel-loads/${load.id}'),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(48),
    child: Center(child: Text('No hay cargas de petróleo para mostrar.')),
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
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
