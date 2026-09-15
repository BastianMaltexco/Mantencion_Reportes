import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/report_history_models.dart';
import 'report_history_controller.dart';

/// Convierte la ruta que entrega Flask en una ruta relativa a la API base.
///
/// `download_path` incluye `/api/v1`, mientras que el `Dio` autenticado ya
/// tiene ese prefijo en `baseUrl`. Conservar ambos producía solicitudes a
/// `/api/v1/api/v1/attachments/{id}`.
String attachmentApiPath(String downloadPath, String apiBaseUrl) {
  final apiBase = Uri.parse(apiBaseUrl);
  final download = Uri.parse(downloadPath);
  if (download.hasScheme &&
      (download.scheme != apiBase.scheme ||
          download.authority != apiBase.authority)) {
    throw const FormatException('La ruta del adjunto no pertenece a la API.');
  }

  final basePath = apiBase.path.replaceFirst(RegExp(r'/+$'), '');
  final downloadPathOnly = download.path;
  if (!downloadPathOnly.startsWith('$basePath/')) {
    throw const FormatException('La ruta privada del adjunto es inválida.');
  }
  return downloadPathOnly.substring(basePath.length);
}

final attachmentImageProvider = FutureProvider.family<Uint8List, String>((
  ref,
  downloadPath,
) async {
  final dio = ref.read(dioProvider);
  final path = attachmentApiPath(downloadPath, dio.options.baseUrl);
  final response = await dio.get<List<int>>(
    path,
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = response.data;
  if (bytes == null || bytes.isEmpty) {
    throw StateError('La imagen no contiene datos.');
  }
  return Uint8List.fromList(bytes);
});

class ReportDetailPage extends ConsumerWidget {
  const ReportDetailPage({super.key, required this.reportId});
  final int reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(reportDetailProvider(reportId));
    return Scaffold(
      appBar: AppBar(title: Text('Reporte #$reportId')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _DetailError(
          message: error.toString(),
          onRetry: () => ref.invalidate(reportDetailProvider(reportId)),
        ),
        data: (report) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CardSection(
              title: report.client,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ValueRow(label: 'Servicio', value: report.serviceType),
                  _ValueRow(label: 'Técnico', value: report.technicianName),
                  _ValueRow(
                    label: 'Área',
                    value: report.areaName ?? 'Sin área',
                  ),
                  _ValueRow(
                    label: 'Sección',
                    value: report.sectionName ?? 'Sin sección',
                  ),
                  _ValueRow(
                    label: 'Maquinaria',
                    value: report.machineryName ?? 'Sin maquinaria',
                  ),
                  _ValueRow(
                    label: 'Creado',
                    value: _format(context, report.createdAt),
                  ),
                  _ValueRow(
                    label: 'Comienzo',
                    value: _format(context, report.taskStartedAt),
                  ),
                  _ValueRow(
                    label: 'Finalización',
                    value: _format(context, report.taskFinishedAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _CardSection(
              title: 'Trabajo realizado',
              child: Text(report.description),
            ),
            const SizedBox(height: 12),
            _CardSection(
              title: 'Checklist',
              child: Column(
                children: report.checklist
                    .map((item) => _ChecklistRow(item: item))
                    .toList(),
              ),
            ),
            if (report.attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _CardSection(
                title: 'Evidencias y adjuntos',
                child: Column(
                  children: report.attachments
                      .map(
                        (attachment) => _AttachmentView(attachment: attachment),
                      )
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _format(BuildContext context, DateTime? value) => value == null
      ? 'No informado'
      : '${MaterialLocalizations.of(context).formatShortDate(value)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
}

class _AttachmentView extends ConsumerWidget {
  const _AttachmentView({required this.attachment});
  final ReportAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!attachment.isImage) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.description_outlined),
        title: Text(
          attachment.originalName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('${attachment.sizeBytes} bytes'),
      );
    }
    final image = ref.watch(attachmentImageProvider(attachment.downloadPath));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            attachment.originalName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          image.when(
            loading: () => const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox(
              height: 80,
              child: Center(child: Text('No fue posible cargar la imagen.')),
            ),
            data: (bytes) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                bytes,
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item});
  final ReportChecklistItem item;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(item.question),
    trailing: Chip(label: Text(item.answer)),
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}

class _CardSection extends StatelessWidget {
  const _CardSection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});
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
