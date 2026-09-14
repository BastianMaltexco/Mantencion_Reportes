# Reportes Mantención

Aplicación Flask para registrar reportes en terreno con SQL Server, usuarios por rol y adjuntos.

## Prueba local

1. Instale SQL Server y el controlador **ODBC Driver 18 for SQL Server**. Cree (si aún no existe) la base `ReportesMantencion`.
2. Ejecute [`script_db.sql`](script_db.sql) en esa base desde SQL Server Management Studio.
3. Copie `.env.example` a `.env` y ajuste las variables `DB_*`, `SECRET_KEY` y las credenciales de administrador. No suba `.env` al repositorio.
4. En PowerShell, en la carpeta del proyecto:

   ```powershell
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   py run.py
   ```

5. Abra `http://127.0.0.1:5000`. El arranque crea el usuario administrador definido en `ADMIN_USERNAME` (correo electrónico) y `ADMIN_PASSWORD` si ese correo todavía no existe.

## Producción

- Configure `SESSION_COOKIE_SECURE=true`, una `SECRET_KEY` aleatoria larga, una cuenta SQL con permisos mínimos sobre estas tablas y una carpeta `UPLOAD_FOLDER` fuera del directorio público del sitio.
- En Linux, use un servidor WSGI delante de Nginx: `gunicorn --workers 3 --bind 127.0.0.1:8000 wsgi:app`.
- En IIS/Windows, instale `wfastcgi`, configure el handler hacia el Python del entorno virtual y apúntelo a `wsgi.py` / `app`; otorgue al pool de IIS permisos de modificación únicamente sobre `UPLOAD_FOLDER`.
- El CDN de Tailwind es práctico para la prueba. Antes de una puesta en producción estricta, compile Tailwind y publique el CSS resultante en `app/static/css/` para evitar depender de un recurso externo.

## Render + Azure SQL Database

El proyecto incluye `Dockerfile` y `render.yaml`. Se usa Docker porque `pyodbc` requiere el paquete de sistema **Microsoft ODBC Driver 18 for SQL Server**. El proceso de producción es Gunicorn con `wsgi:app`, escuchando en `0.0.0.0:$PORT`.

1. Suba los cambios al repositorio y cree un **Blueprint** en Render desde `render.yaml`. No cree el servicio todavía si no desea desplegarlo.
2. En Render copie manualmente las variables siguientes desde su archivo local `.env.azure-test`; no suba ese archivo:

   ```text
   DB_SERVER
   DB_PORT=1433
   DB_NAME=ReportesMantencionTest
   DB_USER
   DB_PASSWORD
   DB_DRIVER=ODBC Driver 18 for SQL Server
   DB_ENCRYPT=yes
   DB_TRUST_SERVER_CERTIFICATE=no
   ```

   Render genera `SECRET_KEY` y el Blueprint no contiene ningún secreto. Mantenga `SESSION_COOKIE_SECURE=true`.
3. Antes del primer deploy, agregue en el firewall del logical server de Azure una regla para la salida de Render. No habilite el acceso público amplio si puede usar una IP de salida estática. La regla actual solo permite la IP local usada durante la migración.
4. Para las pruebas, `UPLOAD_FOLDER=/tmp/reportes-uploads`: los adjuntos se perderán al reiniciar, escalar o redeplegar. Render usa un sistema de archivos efímero. Para conservar archivos, use un disco persistente de Render (requiere servicio de pago) o, preferiblemente, Azure Blob Storage/S3 antes de producción.

La ejecución local no cambia: `py run.py` usa `.env`. Para probar localmente contra Azure: `$env:ENV_FILE = ".env.azure-test"; py run.py`.

## Diseño de datos

El registro de fecha/hora usa `DATETIMEOFFSET(7)` con `SYSDATETIMEOFFSET()` como default de SQL Server. No se recibe desde el cliente y la aplicación no ofrece edición de reportes, conservando el sello de creación.
