import '../../reports/domain/maintenance_report.dart' show iso8601WithOffset;

class FuelGeneratorInput {
  const FuelGeneratorInput({
    required this.number,
    required this.liters,
    required this.hourmeter,
  });

  final int number;
  final String liters;
  final String hourmeter;

  Map<String, dynamic> toJson() => {
    'number': number,
    'liters': _number(liters),
    'hourmeter': _number(hourmeter),
  };

  List<String> validate() {
    final errors = <String>[];
    final parsedLiters = _parse(liters);
    final parsedHourmeter = _parse(hourmeter);
    if (parsedLiters == null || parsedLiters < 0 || parsedLiters >= 750) {
      errors.add('Generador $number: los litros permitidos van de 0 a 749,99.');
    }
    if (parsedHourmeter == null || parsedHourmeter < 0) {
      errors.add('Generador $number: ingrese un horómetro válido no negativo.');
    }
    return errors;
  }

  static double? _parse(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  static num? _number(String value) => _parse(value);
}

class FuelLoadInput {
  const FuelLoadInput({
    required this.loadedAt,
    required this.observations,
    required this.generators,
  });

  final DateTime? loadedAt;
  final String observations;
  final List<FuelGeneratorInput> generators;

  Map<String, dynamic> toJson() => {
    'loaded_at': loadedAt == null ? null : iso8601WithOffset(loadedAt!),
    'observations': observations.trim(),
    'generators': generators.map((generator) => generator.toJson()).toList(),
  };

  List<String> validate({required Set<String> imageKeys}) {
    final errors = <String>[];
    if (loadedAt == null) errors.add('Fecha y hora de carga es obligatoria.');
    if (generators.length != 2 ||
        generators.map((generator) => generator.number).toSet().length != 2 ||
        !generators.map((generator) => generator.number).toSet().containsAll({
          1,
          2,
        })) {
      errors.add('Debe informar exactamente los Generadores 1 y 2.');
    }
    for (final generator in generators) {
      errors.addAll(generator.validate());
      for (final kind in ['water', 'oil']) {
        final key = '${kind}_${generator.number}';
        if (!imageKeys.contains(key)) {
          final label = kind == 'water' ? 'nivel de agua' : 'nivel de aceite';
          errors.add(
            'Generador ${generator.number}: adjunte fotografía de $label.',
          );
        }
      }
    }
    return errors;
  }
}

class FuelLoadSummary {
  const FuelLoadSummary({
    required this.id,
    required this.loadedAt,
    required this.createdAt,
    required this.technicianName,
    this.observations,
  });

  factory FuelLoadSummary.fromJson(Map<String, dynamic> json) =>
      FuelLoadSummary(
        id: json['id'] as int,
        loadedAt: DateTime.parse(json['loaded_at'] as String).toLocal(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        technicianName:
            ((json['technician'] as Map?)?['full_name'] ?? 'Sin técnico')
                .toString(),
        observations: json['observations']?.toString(),
      );

  final int id;
  final DateTime loadedAt;
  final DateTime createdAt;
  final String technicianName;
  final String? observations;
}

class FuelLoadGenerator {
  const FuelLoadGenerator({
    required this.number,
    required this.liters,
    required this.hourmeter,
    required this.waterImagePath,
    required this.oilImagePath,
  });

  factory FuelLoadGenerator.fromJson(Map<String, dynamic> json) =>
      FuelLoadGenerator(
        number: json['number'] as int,
        liters: (json['liters'] as num).toDouble(),
        hourmeter: (json['hourmeter'] as num).toDouble(),
        waterImagePath: json['water_image_path'] as String,
        oilImagePath: json['oil_image_path'] as String,
      );

  final int number;
  final double liters;
  final double hourmeter;
  final String waterImagePath;
  final String oilImagePath;
}

class FuelLoadDetail extends FuelLoadSummary {
  const FuelLoadDetail({
    required super.id,
    required super.loadedAt,
    required super.createdAt,
    required super.technicianName,
    super.observations,
    required this.generators,
  });

  factory FuelLoadDetail.fromJson(Map<String, dynamic> json) => FuelLoadDetail(
    id: json['id'] as int,
    loadedAt: DateTime.parse(json['loaded_at'] as String).toLocal(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    technicianName:
        ((json['technician'] as Map?)?['full_name'] ?? 'Sin técnico')
            .toString(),
    observations: json['observations']?.toString(),
    generators: ((json['generators'] as List?) ?? const [])
        .map(
          (item) => FuelLoadGenerator.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(),
  );

  final List<FuelLoadGenerator> generators;
}

class FuelLoadPage {
  const FuelLoadPage({
    required this.loads,
    required this.page,
    required this.totalPages,
  });

  final List<FuelLoadSummary> loads;
  final int page;
  final int totalPages;
  bool get hasMore => page < totalPages;
}
