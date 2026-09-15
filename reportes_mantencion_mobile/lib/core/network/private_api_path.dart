/// Convierte una ruta privada devuelta por Flask en una ruta relativa a la API
/// base configurada en Dio.
///
/// Flask devuelve rutas como `/api/v1/attachments/42`, mientras que el cliente
/// ya usa una base que termina en `/api/v1`. El resultado correcto para Dio es
/// `/attachments/42`, evitando duplicar el prefijo y manteniendo JWT/refresh.
String privateApiPath(String downloadPath, String apiBaseUrl) {
  final apiBase = Uri.parse(apiBaseUrl);
  final download = Uri.parse(downloadPath);
  if (download.hasScheme &&
      (download.scheme != apiBase.scheme ||
          download.authority != apiBase.authority)) {
    throw const FormatException('La ruta privada no pertenece a la API.');
  }

  final basePath = apiBase.path.replaceFirst(RegExp(r'/+$'), '');
  final downloadPathOnly = download.path;
  if (!downloadPathOnly.startsWith('$basePath/')) {
    throw const FormatException('La ruta privada es inválida.');
  }
  return downloadPathOnly.substring(basePath.length);
}
