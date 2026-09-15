import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/report_history_models.dart';
import 'report_history_controller.dart';

class ReportHistoryPage extends ConsumerWidget {
  const ReportHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(reportHistoryControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de reportes')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _HistoryError(
          message: error.toString(),
          onRetry: () =>
              ref.read(reportHistoryControllerProvider.notifier).refresh(),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: () =>
              ref.read(reportHistoryControllerProvider.notifier).refresh(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.extentAfter < 240) {
                ref.read(reportHistoryControllerProvider.notifier).loadMore();
              }
              return false;
            },
            child: state.reports.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 180),
                      Center(child: Text('No hay reportes disponibles.')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount:
                        state.reports.length + (state.isLoadingMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == state.reports.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final report = state.reports[index];
                      return _ReportListItem(
                        report: report,
                        onTap: () => context.push('/reports/${report.id}'),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _ReportListItem extends StatelessWidget {
  const _ReportListItem({required this.report, required this.onTap});
  final ReportSummary report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Text('#${report.id}')),
      title: Text(report.client, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.serviceType,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${report.machineryName ?? 'Sin maquinaria'} · ${report.technicianName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            MaterialLocalizations.of(context).formatShortDate(report.createdAt),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.message, required this.onRetry});
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
