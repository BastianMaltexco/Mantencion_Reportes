import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalogs/domain/catalog_item.dart';
import '../../catalogs/presentation/catalog_controller.dart';
import '../domain/maintenance_report.dart';
import 'report_submission_controller.dart';

class CreateMaintenanceReportPage extends ConsumerStatefulWidget {
  const CreateMaintenanceReportPage({super.key});

  @override
  ConsumerState<CreateMaintenanceReportPage> createState() =>
      _CreateMaintenanceReportPageState();
}

class _CreateMaintenanceReportPageState
    extends ConsumerState<CreateMaintenanceReportPage> {
  final _formKey = GlobalKey<FormState>();
  final _client = TextEditingController(text: 'Maltexco');
  final _description = TextEditingController();
  final _picker = ImagePicker();
  final _answers = <String, String?>{};
  final _evidence = <String, XFile>{};
  String? _serviceType;
  DateTime? _startedAt;
  DateTime? _finishedAt;

  @override
  void dispose() {
    _client.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime(bool isStart) async {
    final initial = (isStart ? _startedAt : _finishedAt) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      final selected = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _startedAt = selected;
      } else {
        _finishedAt = selected;
      }
    });
  }

  Future<void> _pickEvidence(String key) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar fotografía'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir desde galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await _picker.pickImage(source: source, imageQuality: 85);
    if (image == null || !mounted) return;
    final name = image.name.toLowerCase();
    if (!(name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png'))) {
      _showError('La evidencia debe estar en formato JPG o PNG.');
      return;
    }
    setState(() => _evidence[key] = image);
  }

  bool _requiresEvidence(ChecklistQuestion question) =>
      question.evidenceWhen == _answers[question.key];

  Future<void> _submit(CatalogState catalogs) async {
    if (!_formKey.currentState!.validate()) return;
    final input = MaintenanceReportInput(
      client: _client.text,
      serviceType: _serviceType,
      description: _description.text,
      areaId: catalogs.areaId,
      sectionId: catalogs.sectionId,
      machineryId: catalogs.machineryId,
      taskStartedAt: _startedAt,
      taskFinishedAt: _finishedAt,
      checklist: _answers,
    );
    final errors = input.validate(evidenceKeys: _evidence.keys.toSet());
    if (errors.isNotEmpty) {
      _showError(errors.join('\n'));
      return;
    }
    try {
      final id = await ref
          .read(reportSubmissionProvider.notifier)
          .submit(input, evidence: _evidence);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 44,
          ),
          title: const Text('Reporte creado'),
          content: Text('El reporte #$id fue enviado correctamente.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } on AppException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );

  @override
  Widget build(BuildContext context) {
    final catalogsAsync = ref.watch(catalogControllerProvider);
    final submission = ref.watch(reportSubmissionProvider);
    final user = ref.watch(authControllerProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo reporte de mantención')),
      body: catalogsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _PageError(
          message: error.toString(),
          onRetry: () => ref.invalidate(catalogControllerProvider),
        ),
        data: (catalogs) => Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (user != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(user.fullName),
                    subtitle: Text(
                      'Técnico asignado automáticamente · ${user.role}',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Datos de tarea',
                child: Column(
                  children: [
                    _DateTimeField(
                      label: 'Comienzo de tarea',
                      value: _startedAt,
                      onTap: () => _selectDateTime(true),
                    ),
                    const SizedBox(height: 12),
                    _DateTimeField(
                      label: 'Finalización de tarea',
                      value: _finishedAt,
                      onTap: () => _selectDateTime(false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Equipo',
                child: Column(
                  children: [
                    _CatalogDropdown<Area>(
                      key: const ValueKey('report-area'),
                      label: 'Área',
                      selectedId: _selectedId(
                        catalogs.areas.map((item) => item.id),
                        catalogs.areaId,
                      ),
                      items: catalogs.areas,
                      labelOf: (item) => item.name,
                      onChanged: (id) => ref
                          .read(catalogControllerProvider.notifier)
                          .selectArea(id),
                    ),
                    const SizedBox(height: 12),
                    _CatalogDropdown<Section>(
                      key: ValueKey('report-section-${catalogs.areaId}'),
                      label: 'Sección',
                      selectedId: _selectedId(
                        catalogs.sections.map((item) => item.id),
                        catalogs.sectionId,
                      ),
                      items: catalogs.sections,
                      labelOf: (item) => item.name,
                      enabled:
                          catalogs.areaId != null &&
                          !catalogs.isLoadingSections,
                      isLoading: catalogs.isLoadingSections,
                      onChanged: (id) => ref
                          .read(catalogControllerProvider.notifier)
                          .selectSection(id),
                    ),
                    const SizedBox(height: 12),
                    _CatalogDropdown<Machinery>(
                      key: ValueKey('report-machinery-${catalogs.sectionId}'),
                      label: 'Maquinaria',
                      selectedId: _selectedId(
                        catalogs.machineries.map((item) => item.id),
                        catalogs.machineryId,
                      ),
                      items: catalogs.machineries,
                      labelOf: (item) => item.name,
                      enabled:
                          catalogs.sectionId != null &&
                          !catalogs.isLoadingMachineries,
                      isLoading: catalogs.isLoadingMachineries,
                      onChanged: (id) => ref
                          .read(catalogControllerProvider.notifier)
                          .selectMachinery(id),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Trabajo realizado',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _client,
                      decoration: const InputDecoration(
                        labelText: 'Cliente / Empresa',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Campo obligatorio.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _serviceType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de servicio',
                      ),
                      items: serviceTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(
                                type,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _serviceType = value),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _description,
                      minLines: 4,
                      maxLines: 7,
                      decoration: const InputDecoration(
                        labelText:
                            'Descripción detallada del trabajo realizado',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Campo obligatorio.'
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ..._checklistGroups(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: submission.isSubmitting
                    ? null
                    : () => _submit(catalogs),
                icon: submission.isSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    submission.isSubmitting
                        ? 'Enviando reporte…'
                        : 'Crear reporte',
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _checklistGroups() {
    final groups = <String, List<ChecklistQuestion>>{};
    for (final question in maintenanceChecklist) {
      groups.putIfAbsent(question.group, () => []).add(question);
    }
    return groups.entries
        .map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SectionCard(
              title: entry.key,
              child: Column(
                children: entry.value.map(_checklistQuestion).toList(),
              ),
            ),
          ),
        )
        .toList();
  }

  Widget _checklistQuestion(ChecklistQuestion question) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.question,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: checklistAnswers
              .map(
                (answer) => ButtonSegment(value: answer, label: Text(answer)),
              )
              .toList(),
          selected: _answers[question.key] == null
              ? const {}
              : {_answers[question.key]!},
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          onSelectionChanged: (values) => setState(() {
            _answers[question.key] = values.isEmpty ? null : values.first;
            if (!_requiresEvidence(question)) _evidence.remove(question.key);
          }),
        ),
        if (_requiresEvidence(question)) ...[
          const SizedBox(height: 8),
          _EvidencePicker(
            file: _evidence[question.key],
            onPick: () => _pickEvidence(question.key),
            onRemove: () => setState(() => _evidence.remove(question.key)),
          ),
        ],
      ],
    ),
  );

  int? _selectedId(Iterable<int> ids, int? selectedId) =>
      selectedId != null && ids.where((id) => id == selectedId).length == 1
      ? selectedId
      : null;
}

class _CatalogDropdown<T> extends StatelessWidget {
  const _CatalogDropdown({
    super.key,
    required this.label,
    required this.selectedId,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.enabled = true,
    this.isLoading = false,
  });
  final String label;
  final int? selectedId;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  final bool isLoading;

  int _idOf(T item) => switch (item) {
    Area area => area.id,
    Section section => section.id,
    Machinery machinery => machinery.id,
    _ => throw StateError('Catálogo no soportado'),
  };

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    isExpanded: true,
    initialValue: selectedId,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: isLoading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
    ),
    hint: Text(
      isLoading
          ? 'Cargando…'
          : enabled
          ? (items.isEmpty ? 'No hay opciones' : 'Selecciona una opción')
          : 'Selecciona antes el nivel anterior',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    ),
    selectedItemBuilder: (context) => items
        .map(
          (item) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              labelOf(item),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    items: items
        .map(
          (item) => DropdownMenuItem<int>(
            value: _idOf(item),
            child: Text(
              labelOf(item),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: enabled && !isLoading && items.isNotEmpty ? onChanged : null,
  );
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final selected = value;
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          selected == null
              ? 'Seleccionar fecha y hora'
              : '${MaterialLocalizations.of(context).formatFullDate(selected)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(selected))}',
        ),
      ),
    );
  }
}

class _EvidencePicker extends StatelessWidget {
  const _EvidencePicker({
    required this.file,
    required this.onPick,
    required this.onRemove,
  });
  final XFile? file;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: onPick,
          icon: Icon(
            file == null
                ? Icons.add_a_photo_outlined
                : Icons.check_circle_outline,
          ),
          label: Text(
            file == null
                ? 'Adjuntar fotografía obligatoria'
                : 'Evidencia: ${file!.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      if (file != null)
        IconButton(
          tooltip: 'Quitar evidencia',
          onPressed: onRemove,
          icon: const Icon(Icons.close),
        ),
    ],
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
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
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

class _PageError extends StatelessWidget {
  const _PageError({required this.message, required this.onRetry});
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
