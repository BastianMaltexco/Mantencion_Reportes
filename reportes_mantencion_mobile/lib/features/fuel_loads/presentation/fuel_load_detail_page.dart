import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/private_api_path.dart';
import '../../../core/providers.dart';
import '../domain/fuel_load.dart';
import 'fuel_load_history_controller.dart';

final fuelImageProvider = FutureProvider.family<Uint8List, String>((
  ref,
  path,
) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get<List<int>>(
    privateApiPath(path, dio.options.baseUrl),
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = response.data;
  if (bytes == null || bytes.isEmpty) {
    throw StateError('La imagen no contiene datos.');
  }
  return Uint8List.fromList(bytes);
});

class FuelLoadDetailPage extends ConsumerWidget {
  const FuelLoadDetailPage({super.key, required this.loadId});
  final int loadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(fuelLoadDetailProvider(loadId));
    return Scaffold(
      appBar: AppBar(title: Text('Carga #$loadId')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(fuelLoadDetailProvider(loadId)),
        ),
        data: (load) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CardSection(
              title: 'Datos de carga',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Value(label: 'Técnico', value: load.technicianName),
                  _Value(
                    label: 'Fecha y hora',
                    value:
                        '${MaterialLocalizations.of(context).formatFullDate(load.loadedAt)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(load.loadedAt))}',
                  ),
                  if (load.observations?.isNotEmpty == true)
                    _Value(label: 'Observaciones', value: load.observations!),
                ],
              ),
            ),
            ...load.generators.map(
              (generator) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _GeneratorDetail(generator: generator),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratorDetail extends StatelessWidget {
  const _GeneratorDetail({required this.generator});
  final FuelLoadGenerator generator;

  @override
  Widget build(BuildContext context) => _CardSection(
    title: 'Generador ${generator.number}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Value(label: 'Litros', value: generator.liters.toStringAsFixed(2)),
        _Value(
          label: 'Horómetro',
          value: generator.hourmeter.toStringAsFixed(2),
        ),
        const SizedBox(height: 8),
        _ProtectedImage(label: 'Nivel de agua', path: generator.waterImagePath),
        const SizedBox(height: 16),
        _ProtectedImage(label: 'Nivel de aceite', path: generator.oilImagePath),
      ],
    ),
  );
}

class _ProtectedImage extends ConsumerWidget {
  const _ProtectedImage({required this.label, required this.path});
  final String label;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(fuelImageProvider(path));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        image.when(
          loading: () => const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SizedBox(
            height: 64,
            child: Center(child: Text('No fue posible cargar la imagen.')),
          ),
          data: (bytes) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value});
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}
