import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/fuel_load.dart';
import 'fuel_load_controller.dart';

class FuelLoadHistoryState {
  const FuelLoadHistoryState({
    required this.loads,
    required this.page,
    required this.totalPages,
    this.isLoadingMore = false,
  });

  final List<FuelLoadSummary> loads;
  final int page;
  final int totalPages;
  final bool isLoadingMore;
  bool get hasMore => page < totalPages;
}

final fuelLoadHistoryProvider =
    AsyncNotifierProvider<FuelLoadHistoryController, FuelLoadHistoryState>(
      FuelLoadHistoryController.new,
    );

class FuelLoadHistoryController extends AsyncNotifier<FuelLoadHistoryState> {
  @override
  Future<FuelLoadHistoryState> build() async {
    final result = await ref
        .read(fuelLoadRepositoryProvider)
        .getFuelLoads(page: 1);
    return FuelLoadHistoryState(
      loads: result.loads,
      page: result.page,
      totalPages: result.totalPages,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    state = AsyncData(
      FuelLoadHistoryState(
        loads: current.loads,
        page: current.page,
        totalPages: current.totalPages,
        isLoadingMore: true,
      ),
    );
    try {
      final result = await ref
          .read(fuelLoadRepositoryProvider)
          .getFuelLoads(page: current.page + 1);
      state = AsyncData(
        FuelLoadHistoryState(
          loads: [...current.loads, ...result.loads],
          page: result.page,
          totalPages: result.totalPages,
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

final fuelLoadDetailProvider = FutureProvider.family<FuelLoadDetail, int>((
  ref,
  id,
) {
  return ref.watch(fuelLoadRepositoryProvider).getFuelLoad(id);
});
