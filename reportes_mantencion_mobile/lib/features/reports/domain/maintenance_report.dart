const serviceTypes = <String>[
  'Correctiva',
  'Preventiva',
  'Predictiva',
  'Nueva instalación',
  'Otro',
];

const checklistAnswers = <String>['Si', 'No', 'No aplica'];

/// Definiciones idénticas a `app/services/field_reports.py` y al contrato v1.
/// Flask sigue siendo la autoridad final de las reglas de negocio.
class ChecklistQuestion {
  const ChecklistQuestion({
    required this.key,
    required this.question,
    this.evidenceWhen,
    required this.group,
  });

  final String key;
  final String question;
  final String? evidenceWhen;
  final String group;
}

const maintenanceChecklist = <ChecklistQuestion>[
  ChecklistQuestion(
    key: 'libre_obstrucciones',
    question: '¿Libre de elementos que pueden obstruir el trabajo?',
    evidenceWhen: 'No',
    group: 'Entrega de equipo a mantención',
  ),
  ChecklistQuestion(
    key: 'componentes_mal_estado',
    question: '¿Piezas o componentes en mal estado?',
    evidenceWhen: 'Si',
    group: 'Entrega de equipo a mantención',
  ),
  ChecklistQuestion(
    key: 'falla_constante',
    question: '¿Problema o falla es constante?',
    group: 'Entrega de equipo a mantención',
  ),
  ChecklistQuestion(
    key: 'equipo_energizado',
    question: '¿Entrega de equipo energizado?',
    group: 'Entrega de equipo a producción',
  ),
  ChecklistQuestion(
    key: 'zona_limpia',
    question: '¿Zona de trabajo limpia?',
    evidenceWhen: 'Si',
    group: 'Entrega de equipo a producción',
  ),
  ChecklistQuestion(
    key: 'falla_solucionada',
    question: '¿Problema o falla solucionada?',
    group: 'Entrega de equipo a producción',
  ),
  ChecklistQuestion(
    key: 'protecciones_instaladas',
    question: '¿Protecciones instaladas?',
    group: 'Entrega de equipo a producción',
  ),
];

class MaintenanceReportInput {
  const MaintenanceReportInput({
    required this.client,
    required this.serviceType,
    required this.description,
    required this.areaId,
    required this.sectionId,
    required this.machineryId,
    required this.taskStartedAt,
    required this.taskFinishedAt,
    required this.checklist,
  });

  final String client;
  final String? serviceType;
  final String description;
  final int? areaId;
  final int? sectionId;
  final int? machineryId;
  final DateTime? taskStartedAt;
  final DateTime? taskFinishedAt;
  final Map<String, String?> checklist;

  Map<String, dynamic> toJson() => {
    'client': client.trim(),
    'service_type': serviceType,
    'description': description.trim(),
    'area_id': areaId,
    'section_id': sectionId,
    'machinery_id': machineryId,
    'task_started_at': taskStartedAt == null
        ? null
        : iso8601WithOffset(taskStartedAt!),
    'task_finished_at': taskFinishedAt == null
        ? null
        : iso8601WithOffset(taskFinishedAt!),
    'checklist': maintenanceChecklist
        .map(
          (question) => {
            'key': question.key,
            'answer': checklist[question.key],
          },
        )
        .toList(),
  };

  List<String> validate({required Set<String> evidenceKeys}) {
    final errors = <String>[];
    if (client.trim().isEmpty) errors.add('Cliente/empresa es obligatorio.');
    if (!serviceTypes.contains(serviceType)) {
      errors.add('Seleccione un tipo de servicio válido.');
    }
    if (description.trim().isEmpty) {
      errors.add('La descripción del trabajo es obligatoria.');
    }
    if (areaId == null || sectionId == null || machineryId == null) {
      errors.add('Área, sección y maquinaria son obligatorias.');
    }
    if (taskStartedAt == null || taskFinishedAt == null) {
      errors.add('Indique el comienzo y la finalización de la tarea.');
    } else if (taskFinishedAt!.isBefore(taskStartedAt!)) {
      errors.add('La finalización no puede ser anterior al comienzo.');
    }
    for (final question in maintenanceChecklist) {
      final answer = checklist[question.key];
      if (!checklistAnswers.contains(answer)) {
        errors.add('Responda: ${question.question}');
      } else if (question.evidenceWhen == answer &&
          !evidenceKeys.contains(question.key)) {
        errors.add('Debe adjuntar una imagen para: ${question.question}');
      }
    }
    return errors;
  }
}

String iso8601WithOffset(DateTime value) {
  final local = value.toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${local.toIso8601String()}$sign$hours:$minutes';
}
