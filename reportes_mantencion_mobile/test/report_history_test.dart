import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_mantencion_mobile/features/history/data/report_history_repository.dart';
import 'package:reportes_mantencion_mobile/features/history/domain/report_history_models.dart';
import 'package:reportes_mantencion_mobile/features/history/presentation/report_history_controller.dart';

void main() {
  test(
    'convierte el detalle de reporte y conserva rutas privadas de adjuntos',
    () {
      final detail = ReportDetail.fromJson({
        'id': 21,
        'client': 'Maltexco',
        'service_type': 'Correctivo',
        'description': 'Trabajo realizado',
        'created_at': '2026-09-15T12:00:00Z',
        'task_started_at': '2026-09-15T10:00:00Z',
        'task_finished_at': '2026-09-15T11:00:00Z',
        'technician': {'full_name': 'Técnico de prueba'},
        'area': {'id': 1, 'name': 'MALTA'},
        'section': {'id': 2, 'name': 'REMOJO'},
        'machinery': {'id': 3, 'name': 'TINA - 1'},
        'checklist': [
          {
            'key': 'libre_obstrucciones',
            'question': '¿Libre de obstrucciones?',
            'answer': 'No',
            'evidence_attachment_id': 42,
          },
        ],
        'attachments': [
          {
            'id': 42,
            'original_name': 'evidencia.jpg',
            'mime_type': 'image/jpeg',
            'size_bytes': 800,
            'download_path': '/api/v1/attachments/42',
          },
        ],
      });
      expect(detail.machineryName, 'TINA - 1');
      expect(detail.checklist.single.evidenceAttachmentId, 42);
      expect(detail.attachments.single.isImage, isTrue);
      expect(detail.attachments.single.downloadPath, '/api/v1/attachments/42');
    },
  );

  test(
    'carga y pagina historial sin aplicar filtros de permisos en el móvil',
    () async {
      final repository = _FakeHistoryRepository();
      final container = ProviderContainer(
        overrides: [
          reportHistoryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final first = await container.read(
        reportHistoryControllerProvider.future,
      );
      expect(first.reports.map((report) => report.id), [1]);
      expect(first.hasMore, isTrue);

      await container.read(reportHistoryControllerProvider.notifier).loadMore();
      final combined = container
          .read(reportHistoryControllerProvider)
          .requireValue;
      expect(combined.reports.map((report) => report.id), [1, 2]);
      expect(combined.hasMore, isFalse);
      expect(repository.requestedPages, [1, 2]);
    },
  );
}

class _FakeHistoryRepository implements ReportHistoryDataSource {
  final requestedPages = <int>[];

  @override
  Future<ReportDetail> getReport(int reportId) => throw UnimplementedError();

  @override
  Future<ReportPage> getReports({required int page, int pageSize = 20}) async {
    requestedPages.add(page);
    return page == 1
        ? ReportPage(reports: [_report(1)], page: 1, totalPages: 2)
        : ReportPage(reports: [_report(2)], page: 2, totalPages: 2);
  }

  ReportSummary _report(int id) => ReportSummary(
    id: id,
    client: 'Maltexco',
    serviceType: 'Correctivo',
    description: 'Prueba',
    createdAt: DateTime(2026, 9, 15),
    technicianName: 'Técnico',
    machineryName: 'TINA - $id',
  );
}
