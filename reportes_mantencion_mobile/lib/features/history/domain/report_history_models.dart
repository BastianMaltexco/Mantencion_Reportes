class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.client,
    required this.serviceType,
    required this.description,
    required this.createdAt,
    required this.technicianName,
    this.areaName,
    this.sectionName,
    this.machineryName,
  });

  factory ReportSummary.fromJson(Map<String, dynamic> json) => ReportSummary(
    id: json['id'] as int,
    client: json['client'] as String,
    serviceType: json['service_type'] as String,
    description: json['description'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    technicianName:
        ((json['technician'] as Map?)?['full_name'] ?? 'Sin técnico')
            .toString(),
    areaName: ((json['area'] as Map?)?['name'])?.toString(),
    sectionName: ((json['section'] as Map?)?['name'])?.toString(),
    machineryName: ((json['machinery'] as Map?)?['name'])?.toString(),
  );

  final int id;
  final String client;
  final String serviceType;
  final String description;
  final DateTime createdAt;
  final String technicianName;
  final String? areaName;
  final String? sectionName;
  final String? machineryName;
}

class ReportChecklistItem {
  const ReportChecklistItem({
    required this.key,
    required this.question,
    required this.answer,
    this.evidenceAttachmentId,
  });

  factory ReportChecklistItem.fromJson(Map<String, dynamic> json) =>
      ReportChecklistItem(
        key: json['key'] as String,
        question: json['question'] as String,
        answer: json['answer'] as String,
        evidenceAttachmentId: json['evidence_attachment_id'] as int?,
      );

  final String key;
  final String question;
  final String answer;
  final int? evidenceAttachmentId;
}

class ReportAttachment {
  const ReportAttachment({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.sizeBytes,
    required this.downloadPath,
  });

  factory ReportAttachment.fromJson(Map<String, dynamic> json) =>
      ReportAttachment(
        id: json['id'] as int,
        originalName: json['original_name'] as String,
        mimeType: json['mime_type'] as String,
        sizeBytes: json['size_bytes'] as int,
        downloadPath: json['download_path'] as String,
      );

  final int id;
  final String originalName;
  final String mimeType;
  final int sizeBytes;
  final String downloadPath;

  bool get isImage => mimeType.startsWith('image/');
}

class ReportDetail extends ReportSummary {
  const ReportDetail({
    required super.id,
    required super.client,
    required super.serviceType,
    required super.description,
    required super.createdAt,
    required super.technicianName,
    super.areaName,
    super.sectionName,
    super.machineryName,
    this.taskStartedAt,
    this.taskFinishedAt,
    required this.checklist,
    required this.attachments,
  });

  factory ReportDetail.fromJson(Map<String, dynamic> json) => ReportDetail(
    id: json['id'] as int,
    client: json['client'] as String,
    serviceType: json['service_type'] as String,
    description: json['description'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    technicianName:
        ((json['technician'] as Map?)?['full_name'] ?? 'Sin técnico')
            .toString(),
    areaName: ((json['area'] as Map?)?['name'])?.toString(),
    sectionName: ((json['section'] as Map?)?['name'])?.toString(),
    machineryName: ((json['machinery'] as Map?)?['name'])?.toString(),
    taskStartedAt: _date(json['task_started_at']),
    taskFinishedAt: _date(json['task_finished_at']),
    checklist: ((json['checklist'] as List?) ?? const [])
        .map(
          (item) => ReportChecklistItem.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(),
    attachments: ((json['attachments'] as List?) ?? const [])
        .map(
          (item) =>
              ReportAttachment.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );

  final DateTime? taskStartedAt;
  final DateTime? taskFinishedAt;
  final List<ReportChecklistItem> checklist;
  final List<ReportAttachment> attachments;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.parse(value).toLocal() : null;
}

class ReportPage {
  const ReportPage({
    required this.reports,
    required this.page,
    required this.totalPages,
  });
  final List<ReportSummary> reports;
  final int page;
  final int totalPages;
  bool get hasMore => page < totalPages;
}
