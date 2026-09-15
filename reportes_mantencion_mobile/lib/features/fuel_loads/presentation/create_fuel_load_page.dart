import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/fuel_load.dart';
import 'fuel_load_controller.dart';

class CreateFuelLoadPage extends ConsumerStatefulWidget {
  const CreateFuelLoadPage({super.key});

  @override
  ConsumerState<CreateFuelLoadPage> createState() => _CreateFuelLoadPageState();
}

class _CreateFuelLoadPageState extends ConsumerState<CreateFuelLoadPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _observations = TextEditingController();
  final _liters1 = TextEditingController();
  final _hourmeter1 = TextEditingController();
  final _liters2 = TextEditingController();
  final _hourmeter2 = TextEditingController();
  final _images = <String, XFile>{};
  DateTime? _loadedAt;

  @override
  void dispose() {
    _observations.dispose();
    _liters1.dispose();
    _hourmeter1.dispose();
    _liters2.dispose();
    _hourmeter2.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime() async {
    final initial = _loadedAt ?? DateTime.now();
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
      _loadedAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickImage(String key) async {
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
      _showError('La fotografía debe estar en formato JPG o PNG.');
      return;
    }
    setState(() => _images[key] = image);
  }

  FuelLoadInput _input() => FuelLoadInput(
    loadedAt: _loadedAt,
    observations: _observations.text,
    generators: [
      FuelGeneratorInput(
        number: 1,
        liters: _liters1.text,
        hourmeter: _hourmeter1.text,
      ),
      FuelGeneratorInput(
        number: 2,
        liters: _liters2.text,
        hourmeter: _hourmeter2.text,
      ),
    ],
  );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final input = _input();
    final errors = input.validate(imageKeys: _images.keys.toSet());
    if (errors.isNotEmpty) {
      _showError(errors.join('\n'));
      return;
    }
    try {
      final id = await ref
          .read(fuelLoadSubmissionProvider.notifier)
          .submit(input, _images);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 44,
          ),
          title: const Text('Carga registrada'),
          content: Text('La carga de petróleo #$id fue enviada correctamente.'),
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
    final submission = ref.watch(fuelLoadSubmissionProvider);
    final user = ref.watch(authControllerProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Carga de petróleo')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (user != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(user.fullName),
                  subtitle: const Text('Técnico asignado automáticamente'),
                ),
              ),
            const SizedBox(height: 12),
            _CardSection(
              title: 'Fecha y hora de carga',
              child: InkWell(
                onTap: _selectDateTime,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha y hora de carga *',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _loadedAt == null
                        ? 'Seleccionar fecha y hora'
                        : '${MaterialLocalizations.of(context).formatFullDate(_loadedAt!)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_loadedAt!))}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _GeneratorCard(
              number: 1,
              liters: _liters1,
              hourmeter: _hourmeter1,
              images: _images,
              onPick: _pickImage,
              onRemove: (key) => setState(() => _images.remove(key)),
            ),
            const SizedBox(height: 12),
            _GeneratorCard(
              number: 2,
              liters: _liters2,
              hourmeter: _hourmeter2,
              images: _images,
              onPick: _pickImage,
              onRemove: (key) => setState(() => _images.remove(key)),
            ),
            const SizedBox(height: 12),
            _CardSection(
              title: 'Observaciones generales',
              child: TextFormField(
                controller: _observations,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (submission.isSubmitting) ...[
              LinearProgressIndicator(
                value: submission.progress == 0 ? null : submission.progress,
              ),
              const SizedBox(height: 8),
              Text(
                'Enviando fotografías… ${(submission.progress * 100).round()}%',
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: submission.isSubmitting ? null : _submit,
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
                      ? 'Enviando carga…'
                      : 'Registrar carga',
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _GeneratorCard extends StatelessWidget {
  const _GeneratorCard({
    required this.number,
    required this.liters,
    required this.hourmeter,
    required this.images,
    required this.onPick,
    required this.onRemove,
  });
  final int number;
  final TextEditingController liters;
  final TextEditingController hourmeter;
  final Map<String, XFile> images;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => _CardSection(
    title: 'Generador $number',
    child: Column(
      children: [
        TextFormField(
          controller: liters,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_FuelNumberFormatter(maximum: 749.99)],
          decoration: const InputDecoration(
            labelText: 'Cantidad de litros *',
            helperText: 'Debe ser menor a 750 litros.',
          ),
          validator: (value) {
            final liters = double.tryParse((value ?? '').replaceAll(',', '.'));
            return liters == null || liters < 0 || liters >= 750
                ? 'Ingrese un valor entre 0 y 749,99.'
                : null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: hourmeter,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_FuelNumberFormatter()],
          decoration: const InputDecoration(
            labelText: 'Horómetro *',
            helperText: 'Horas de funcionamiento.',
          ),
          validator: (value) {
            final hours = double.tryParse((value ?? '').replaceAll(',', '.'));
            return hours == null || hours < 0
                ? 'Ingrese un horómetro válido.'
                : null;
          },
        ),
        const SizedBox(height: 16),
        _PhotoField(
          title: 'Nivel de agua Generador $number',
          file: images['water_$number'],
          onPick: () => onPick('water_$number'),
          onRemove: () => onRemove('water_$number'),
        ),
        const SizedBox(height: 12),
        _PhotoField(
          title: 'Nivel de aceite Generador $number',
          file: images['oil_$number'],
          onPick: () => onPick('oil_$number'),
          onRemove: () => onRemove('oil_$number'),
        ),
      ],
    ),
  );
}

class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.title,
    required this.file,
    required this.onPick,
    required this.onRemove,
  });
  final String title;
  final XFile? file;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$title *', style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: onPick,
        icon: Icon(
          file == null
              ? Icons.add_a_photo_outlined
              : Icons.photo_camera_back_outlined,
        ),
        label: Text(
          file == null
              ? 'Tomar o seleccionar fotografía'
              : 'Cambiar fotografía',
        ),
      ),
      if (file != null) ...[
        const SizedBox(height: 8),
        FutureBuilder<Uint8List>(
          future: file!.readAsBytes(),
          builder: (context, snapshot) => snapshot.hasData
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    snapshot.data!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                )
              : const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            label: const Text('Quitar'),
          ),
        ),
      ],
    ],
  );
}

class _FuelNumberFormatter extends TextInputFormatter {
  _FuelNumberFormatter({this.maximum});
  final double? maximum;
  static final _allowed = RegExp(r'^\d{0,3}([,.]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!_allowed.hasMatch(newValue.text)) return oldValue;
    final parsed = double.tryParse(newValue.text.replaceAll(',', '.'));
    if (maximum != null && parsed != null && parsed > maximum!) return oldValue;
    return newValue;
  }
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
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}
