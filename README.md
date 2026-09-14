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

## Diseño de datos

El registro de fecha/hora usa `DATETIMEOFFSET(7)` con `SYSDATETIMEOFFSET()` como default de SQL Server. No se recibe desde el cliente y la aplicación no ofrece edición de reportes, conservando el sello de creación.
