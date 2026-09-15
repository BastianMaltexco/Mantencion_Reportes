import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/report_history_repository.dart';
import '../domain/report_history_models.dart';

class ReportHistoryState {
  const ReportHistoryState({
    this.reports = const [],
    this.page = 1,
    this.totalPages = 1,
    this.isLoadingMore = false,
  });
  final List<ReportSummary> reports;
  final int page;
  final int totalPages;
  final bool isLoadingMore;
  bool get hasMore => page < totalPages;
}

final reportHistoryRepositoryProvider = Provider<ReportHistoryDataSource>(
  (ref) => ReportHistoryRepository(ref.watch(dioProvider)),
);
final reportHistoryControllerProvider =
    AsyncNotifierProvider<ReportHistoryController, ReportHistoryState>(
      ReportHistoryController.new,
    );

class ReportHistoryController extends AsyncNotifier<ReportHistoryState> {
  @override
  Future<ReportHistoryState> build() async {
    final page = await ref
        .read(reportHistoryRepositoryProvider)
        .getReports(page: 1);
    return ReportHistoryState(
      reports: page.reports,
      page: page.page,
      totalPages: page.totalPages,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final page = await ref
          .read(reportHistoryRepositoryProvider)
          .getReports(page: 1);
      state = AsyncData(
        ReportHistoryState(
          reports: page.reports,
          page: page.page,
          totalPages: page.totalPages,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    state = AsyncData(
      ReportHistoryState(
        reports: current.reports,
        page: current.page,
        totalPages: current.totalPages,
        isLoadingMore: true,
      ),
    );
    try {
      final next = await ref
          .read(reportHistoryRepositoryProvider)
          .getReports(page: current.page + 1);
      state = AsyncData(
        ReportHistoryState(
          reports: [...current.reports, ...next.reports],
          page: next.page,
          totalPages: next.totalPages,
        ),
      );
    } catch (_) {
      // Se conserva el historial ya cargado; el usuario puede reintentar al final.
      state = AsyncData(current);
    }
  }
}

final reportDetailProvider = FutureProvider.family<ReportDetail, int>(
  (ref, reportId) =>
      ref.read(reportHistoryRepositoryProvider).getReport(reportId),
);
