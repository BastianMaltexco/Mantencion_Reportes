import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../data/fuel_load_repository.dart';
import '../domain/fuel_load.dart';

class FuelLoadSubmissionState {
  const FuelLoadSubmissionState({this.isSubmitting = false, this.progress = 0});
  final bool isSubmitting;
  final double progress;
}

final fuelLoadRepositoryProvider = Provider<FuelLoadDataSource>(
  (ref) => FuelLoadRepository(ref.watch(dioProvider)),
);

final fuelLoadSubmissionProvider =
    NotifierProvider<FuelLoadSubmissionController, FuelLoadSubmissionState>(
      FuelLoadSubmissionController.new,
    );

class FuelLoadSubmissionController extends Notifier<FuelLoadSubmissionState> {
  @override
  FuelLoadSubmissionState build() => const FuelLoadSubmissionState();

  Future<int> submit(FuelLoadInput load, Map<String, XFile> images) async {
    state = const FuelLoadSubmissionState(isSubmitting: true);
    try {
      final id = await ref
          .read(fuelLoadRepositoryProvider)
          .createFuelLoad(
            load,
            images: images,
            onSendProgress: (sent, total) {
              if (total > 0) {
                state = FuelLoadSubmissionState(
                  isSubmitting: true,
                  progress: sent / total,
                );
              }
            },
          );
      state = const FuelLoadSubmissionState();
      return id;
    } catch (_) {
      state = const FuelLoadSubmissionState();
      rethrow;
    }
  }
}
