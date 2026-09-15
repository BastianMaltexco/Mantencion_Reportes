import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers.dart';
import '../data/report_repository.dart';
import '../domain/maintenance_report.dart';

class ReportSubmissionState {
  const ReportSubmissionState({
    this.isSubmitting = false,
    this.createdReportId,
  });
  final bool isSubmitting;
  final int? createdReportId;
}

final reportRepositoryProvider = Provider<ReportDataSource>(
  (ref) => ReportRepository(ref.watch(dioProvider)),
);
final reportSubmissionProvider =
    NotifierProvider<ReportSubmissionController, ReportSubmissionState>(
      ReportSubmissionController.new,
    );

class ReportSubmissionController extends Notifier<ReportSubmissionState> {
  @override
  ReportSubmissionState build() => const ReportSubmissionState();

  Future<int> submit(
    MaintenanceReportInput report, {
    required Map<String, XFile> evidence,
  }) async {
    state = const ReportSubmissionState(isSubmitting: true);
    try {
      final reportId = await ref
          .read(reportRepositoryProvider)
          .createMaintenanceReport(report, evidence: evidence);
      state = ReportSubmissionState(createdReportId: reportId);
      return reportId;
    } catch (_) {
      state = const ReportSubmissionState();
      rethrow;
    }
  }
}
