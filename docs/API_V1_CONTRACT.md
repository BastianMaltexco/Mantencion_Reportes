# Contrato API REST v1

Base URL: `https://<dominio>/api/v1`. La aplicación Flutter se comunica solo
con esta API HTTPS; jamás con Azure SQL ni Azure Blob Storage.

## Convenciones

- Todas las fechas se representan en ISO-8601 con zona UTC (`Z`).
- Los cuerpos de solicitud deben usar `Content-Type: application/json`.
- Las respuestas exitosas usan `{ "data": ..., "request_id": "..." }`.
- Las respuestas de error usan el único formato:

```json
{
  "error": {
    "code": "validation_error",
    "message": "username y password son obligatorios.",
    "details": { "campo": "..." },
    "request_id": "uuid"
  }
}
```

`details` es opcional. El cliente debe usar `code` para su lógica y `message`
para mostrar texto. Puede enviar `X-Request-ID`; si no, el servidor lo genera.

## Autenticación y autorización — implementado

El access token es JWT HS256, dura 15 minutos por defecto y se envía como
`Authorization: Bearer <access_token>`. El refresh token es opaco, dura 30
días por defecto, se almacena únicamente en el almacenamiento seguro del móvil
y se rota en cada renovación. Solo su HMAC-SHA256 se persiste en la tabla
`dbo.ApiRefreshTokens`. Cerrar sesión revoca el refresh token; un access token
ya emitido puede vivir como máximo hasta su expiración.

| Método y ruta | Autorización | Estado | Descripción |
|---|---|---|---|
| `GET /health` | Pública | Implementado | Salud de API v1. |
| `POST /auth/login` | Pública | Implementado | Recibe `username`, `password`, opcional `client_name`; devuelve par de tokens y usuario. |
| `POST /auth/refresh` | Pública | Implementado | Recibe `refresh_token`; lo rota y devuelve un par nuevo. |
| `POST /auth/logout` | Pública | Implementado | Recibe `refresh_token`; lo revoca de forma idempotente. |
| `GET /auth/me` | Bearer | Implementado | Perfil del usuario autenticado. |
| `GET /admin/status` | Bearer, Administrador | Implementado | Verificación mínima de control de rol. |

Un usuario desactivado no puede iniciar, renovar ni usar tokens. Los roles se
toman de `dbo.Usuarios.Rol`. En esta etapa el rol `Administrador` es el único
requerido explícitamente por `/admin/status`; el decorador reutilizable permite
proteger los recursos administrativos que se agreguen después.

## Ejemplos

```http
POST /api/v1/auth/login
Content-Type: application/json

{"username":"tecnico@empresa.cl","password":"***","client_name":"Flutter Android"}
```

```json
{
  "data": {
    "access_token": "eyJ...",
    "token_type": "Bearer",
    "expires_in": 900,
    "refresh_token": "...",
    "refresh_expires_in": 2592000,
    "user": {"id": 8, "username": "tecnico@empresa.cl", "full_name": "Técnico", "role": "Técnico/Operativo"}
  },
  "request_id": "uuid"
}
```

## Catálogos e historial - implementado

Todos requieren Bearer JWT. Los técnicos solo ven sus propios reportes y cargas;
Administradores pueden consultar todos y filtrar por `technician_id`.

| Método y ruta | Descripción |
|---|---|
| `GET /areas` | Áreas activas. |
| `GET /sections?area_id=` | Secciones activas de un área activa. `area_id` es obligatorio. |
| `GET /machineries?section_id=` | Maquinarias activas de una sección activa. `section_id` es obligatorio. |
| `GET /reports` | Historial de mantención. Filtros: `date_from`, `date_to`, `area_id`, `section_id`, `machinery_id`, `technician_id`, `service_type`, `page`, `page_size`. |
| `GET /reports/{id}` | Reporte, checklist y metadatos de adjuntos. Aún no entrega el contenido de archivos. |
| `GET /fuel-loads` | Historial de cargas. Filtros: `date_from`, `date_to`, `technician_id`, `page`, `page_size`. |
| `GET /fuel-loads/{id}` | Carga y dos generadores con evidencia registrada. |
| `GET /attachments/{id}` | Descarga privada de un adjunto autorizado. |
| `GET /fuel-loads/{id}/generators/{number}/images/{water|oil}` | Descarga privada de una foto autorizada. |
| `GET /dashboard/summary` | Agregaciones autorizadas para Dashboard móvil. |

`page` comienza en 1 y `page_size` va de 1 a 100 (25 por defecto). Las listas
devuelven `pagination: {page, page_size, total, total_pages}`. Las fechas de
filtro usan ISO-8601; una fecha sin hora en `date_to` incluye el día completo.

## Dashboard - implementado

`GET /dashboard/summary` calcula en SQL/Flask los totales, días activos,
series diarias, distribuciones por área/sección/maquinaria/servicio y actividad
cronológica paginada. Acepta `date_from`, `date_to`, `technician_id`,
`area_id`, `section_id`, `machinery_id`, `service_type`,
`record_type=all|maintenance|fuel`, `activity_page` y `activity_page_size`.

Área, sección y maquinaria se validan como jerarquía. Las cargas de petróleo
no tienen esas relaciones: esos filtros y distribuciones aplican solo a
mantención. Administradores pueden filtrar técnicos; un Técnico queda forzado
por Flask a sus propios registros y un `technician_id` ajeno recibe
`403 insufficient_role`.

## Creación - implementado

`POST /reports` y `POST /fuel-loads` requieren Bearer JWT y asignan el técnico
desde el token: nunca aceptan un técnico enviado por el cliente.

Ambos aceptan `application/json` cuando no necesitan archivos. Para evidencias
o fotografías usan `multipart/form-data`, con un campo textual `payload` que
contiene el mismo JSON y los archivos indicados abajo. Esto permite reutilizar
literalmente las mismas reglas de negocio de la interfaz web.

### POST /reports

`payload` debe incluir `client`, `service_type`, `description`, `area_id`,
`section_id`, `machinery_id`, `task_started_at`, `task_finished_at` y una lista
`checklist` de los siete objetos `{key, answer}`. Las respuestas válidas son
`Si`, `No` y `No aplica`. Las claves son: `libre_obstrucciones`,
`componentes_mal_estado`, `falla_constante`, `equipo_energizado`,
`zona_limpia`, `falla_solucionada`, `protecciones_instaladas`.

Las evidencias se adjuntan con los nombres `evidence_libre_obstrucciones`,
`evidence_componentes_mal_estado` y `evidence_zona_limpia`; deben ser JPG/PNG
cuando corresponda: `No` para obstrucciones y `Si` para componentes o zona
limpia. Los adjuntos generales opcionales se envían repetidos como
`attachments` (JPG, PNG, PDF, Word o Excel). Una condición sin evidencia
retorna HTTP 422 con `code=evidence_required`.

### POST /fuel-loads

`payload` contiene `loaded_at`, `observations` opcional y `generators`, lista
con dos objetos `{number: 1|2, liters, hourmeter}`. El límite estricto es
`0 <= liters < 750`; el horómetro no puede ser negativo. Es obligatorio enviar
en multipart las cuatro fotos JPG/PNG: `water_1`, `oil_1`, `water_2`, `oil_2`.
Sin ellas se devuelve HTTP 422 `evidence_required`.

Los archivos usan `FILE_STORAGE_BACKEND=local` durante desarrollo y
`FILE_STORAGE_BACKEND=azure_blob` en Render. Azure Blob Storage permanece
privado: la base almacena solo claves de objeto, no URLs, y las descargas pasan
por los endpoints autenticados indicados. Flutter seguirá enviando y recibiendo
archivos exclusivamente mediante Flask.

## Recursos reservados para etapas posteriores

El contrato se ampliará sin romper `/api/v1` para: usuarios, borradores,
edición, envío, revisiones/correcciones vinculadas, adjuntos descargables y
sincronización. La edición se permitirá solo cuando `estado=Borrador`; enviar
bloqueará el reporte y las correcciones serán revisiones vinculadas, no cambios
del original.
