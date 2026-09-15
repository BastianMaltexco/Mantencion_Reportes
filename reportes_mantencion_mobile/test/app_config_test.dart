import 'package:flutter_test/flutter_test.dart';
import 'package:reportes_mantencion_mobile/core/config/app_config.dart';
import 'package:reportes_mantencion_mobile/features/auth/domain/authenticated_user.dart';

void main() {
  test('la URL de producción predeterminada usa HTTPS y el prefijo v1', () {
    final config = AppConfig.fromEnvironment();
    expect(config.apiBaseUrl, startsWith('https://'));
    expect(config.apiBaseUrl, endsWith('/api/v1'));
  });

  test('identifica el rol administrador desde la respuesta API', () {
    final user = AuthenticatedUser.fromJson({
      'id': 1,
      'username': 'admin@maltexco.cl',
      'full_name': 'Administrador inicial',
      'role': 'Administrador',
    });
    expect(user.isAdministrator, isTrue);
  });
}
