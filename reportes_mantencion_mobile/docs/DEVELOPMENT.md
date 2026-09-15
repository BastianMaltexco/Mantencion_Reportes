# Desarrollo móvil

La aplicación Flutter usa una única base de código para Android e iOS y consume
solamente la API HTTPS Flask. No se conecta a Azure SQL ni a Azure Blob Storage.

## Ejecución de producción

```powershell
C:\src\flutter\bin\flutter.bat run --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://mantencion-reportes.onrender.com/api/v1
```

## Ejecución de desarrollo

Los valores se inyectan por `--dart-define`; no se crean archivos con tokens,
contraseñas ni credenciales. En el emulador Android, una API Flask local suele
ser accesible con `10.0.2.2`:

```powershell
C:\src\flutter\bin\flutter.bat run --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://10.0.2.2:5000/api/v1
```

Para Render se debe mantener HTTPS. La API desplegada entrega el usuario actual
en `GET /api/v1/auth/me`; la aplicación usa esa ruta del contrato existente.

## Alcance actual

- Login, refresh automático, logout y persistencia segura de tokens.
- Navegación basada en rol y consulta encadenada de áreas, secciones y máquinas.
- Pendiente: formularios, cargas de petróleo, archivos, modo offline y sincronización.
