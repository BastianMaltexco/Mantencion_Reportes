import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_mantencion_mobile/features/reports/domain/maintenance_report.dart';

void main() {
  MaintenanceReportInput validInput({Map<String, String?>? checklist}) =>
      MaintenanceReportInput(
        client: 'Maltexco',
        serviceType: 'Correctivo',
        description: 'Se realizó el trabajo de prueba.',
        areaId: 1,
        sectionId: 2,
        machineryId: 3,
        taskStartedAt: DateTime(2026, 9, 15, 8),
        taskFinishedAt: DateTime(2026, 9, 15, 9),
        checklist:
            checklist ??
            const {
              'libre_obstrucciones': 'No',
              'componentes_mal_estado': 'Si',
              'falla_constante': 'No aplica',
              'equipo_energizado': 'Si',
              'zona_limpia': 'Si',
              'falla_solucionada': 'Si',
              'protecciones_instaladas': 'Si',
            },
      );

  test('exige exactamente las evidencias condicionales del contrato Flask', () {
    final errors = validInput().validate(evidenceKeys: const {});
    expect(errors.join(' '), contains('obstruir'));
    expect(errors.join(' '), contains('componentes'));
    expect(errors.join(' '), contains('Zona de trabajo limpia'));
  });

  test(
    'acepta un reporte cuando las tres evidencias requeridas están presentes',
    () {
      final errors = validInput().validate(
        evidenceKeys: const {
          'libre_obstrucciones',
          'componentes_mal_estado',
          'zona_limpia',
        },
      );
      expect(errors, isEmpty);
    },
  );

  test('no exige evidencia cuando las respuestas no activan la condición', () {
    final input = validInput(
      checklist: const {
        'libre_obstrucciones': 'Si',
        'componentes_mal_estado': 'No',
        'falla_constante': 'No aplica',
        'equipo_energizado': 'Si',
        'zona_limpia': 'No',
        'falla_solucionada': 'Si',
        'protecciones_instaladas': 'Si',
      },
    );
    expect(input.validate(evidenceKeys: const {}), isEmpty);
  });

  test('rechaza una finalización anterior al comienzo antes del envío', () {
    final input = MaintenanceReportInput(
      client: 'Maltexco',
      serviceType: 'Correctivo',
      description: 'Trabajo',
      areaId: 1,
      sectionId: 2,
      machineryId: 3,
      taskStartedAt: DateTime(2026, 9, 15, 10),
      taskFinishedAt: DateTime(2026, 9, 15, 9),
      checklist: const {
        'libre_obstrucciones': 'Si',
        'componentes_mal_estado': 'No',
        'falla_constante': 'No aplica',
        'equipo_energizado': 'Si',
        'zona_limpia': 'No',
        'falla_solucionada': 'Si',
        'protecciones_instaladas': 'Si',
      },
    );
    expect(
      input.validate(evidenceKeys: const {}).join(' '),
      contains('anterior al comienzo'),
    );
  });

  test('genera las claves y fechas que espera el payload de API', () {
    final payload = validInput().toJson();
    expect(payload['area_id'], 1);
    expect(payload['checklist'], hasLength(7));
    expect(payload['task_started_at'], contains(RegExp(r'[+-]\d{2}:\d{2}$')));
  });
}
