/// Valores compilados con `--dart-define`; no contiene secretos.
class AppConfig {
  const AppConfig._({required this.environment, required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    const environment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'production',
    );
    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://mantencion-reportes.onrender.com/api/v1',
    );
    return AppConfig._(
      environment: environment,
      apiBaseUrl: apiBaseUrl.replaceFirst(RegExp(r'/+$'), ''),
    );
  }

  final String environment;
  final String apiBaseUrl;

  bool get isProduction => environment == 'production';
}
