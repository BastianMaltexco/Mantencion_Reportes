"""Genera la bitácora técnica del proyecto Reportes Mantención sin secretos."""

from __future__ import annotations

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "pdf" / "Reportes_Mantencion_PDF.pdf"


def styles():
    base = getSampleStyleSheet()
    base.add(ParagraphStyle(
        name="TitleCustom", parent=base["Title"], fontName="Helvetica-Bold",
        fontSize=24, leading=29, textColor=colors.HexColor("#173B7A"), alignment=TA_CENTER,
        spaceAfter=18,
    ))
    base.add(ParagraphStyle(
        name="Subtitle", parent=base["Normal"], fontName="Helvetica", fontSize=11,
        leading=16, textColor=colors.HexColor("#4B5563"), alignment=TA_CENTER, spaceAfter=26,
    ))
    base.add(ParagraphStyle(
        name="H1Custom", parent=base["Heading1"], fontName="Helvetica-Bold", fontSize=17,
        leading=22, textColor=colors.HexColor("#173B7A"), spaceBefore=10, spaceAfter=10,
    ))
    base.add(ParagraphStyle(
        name="H2Custom", parent=base["Heading2"], fontName="Helvetica-Bold", fontSize=12,
        leading=16, textColor=colors.HexColor("#1D4ED8"), spaceBefore=10, spaceAfter=6,
    ))
    base.add(ParagraphStyle(
        name="BodyCustom", parent=base["BodyText"], fontName="Helvetica", fontSize=9.3,
        leading=14, spaceAfter=6,
    ))
    base.add(ParagraphStyle(
        name="Small", parent=base["BodyText"], fontName="Helvetica", fontSize=8,
        leading=11, textColor=colors.HexColor("#4B5563"), spaceAfter=4,
    ))
    base.add(ParagraphStyle(
        name="TableHead", parent=base["BodyText"], fontName="Helvetica-Bold", fontSize=8,
        leading=10, textColor=colors.white,
    ))
    base.add(ParagraphStyle(
        name="TableCell", parent=base["BodyText"], fontName="Helvetica", fontSize=7.7,
        leading=10,
    ))
    return base


S = styles()


def p(text: str, style="BodyCustom"):
    return Paragraph(text, S[style])


def bullet(items):
    return KeepTogether([p("- " + item) for item in items] + [Spacer(1, 3)])


def grid(headers, rows, widths):
    data = [[p(h, "TableHead") for h in headers]]
    for row in rows:
        data.append([p(str(cell), "TableCell") for cell in row])
    table = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1D4ED8")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#CBD5E1")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BACKGROUND", (0, 1), (-1, -1), colors.HexColor("#F8FAFC")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.HexColor("#FFFFFF"), colors.HexColor("#F8FAFC")]),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    return table


def code(text: str):
    return KeepTogether([
        Spacer(1, 3),
        Preformatted(text, ParagraphStyle(
            "CodeBlock", fontName="Courier", fontSize=7.1, leading=9.2,
            leftIndent=7, rightIndent=7, borderPadding=6,
            backColor=colors.HexColor("#F1F5F9"), borderColor=colors.HexColor("#CBD5E1"),
            borderWidth=0.25, borderRadius=2,
        )),
        Spacer(1, 5),
    ])


def section(title: str):
    return [p(title, "H1Custom")]


def footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor("#CBD5E1"))
    canvas.line(doc.leftMargin, 1.25 * cm, A4[0] - doc.rightMargin, 1.25 * cm)
    canvas.setFillColor(colors.HexColor("#64748B"))
    canvas.setFont("Helvetica", 7.5)
    canvas.drawString(doc.leftMargin, 0.82 * cm, "Reportes Mantención - Bitácora técnica")
    canvas.drawRightString(A4[0] - doc.rightMargin, 0.82 * cm, f"Página {doc.page}")
    canvas.restoreState()


def story():
    flow = []
    flow.extend([
        Spacer(1, 4.0 * cm),
        p("Reportes Mantención", "TitleCustom"),
        p("Bitácora técnica del proyecto - Base de datos, Flask, Azure SQL, API móvil, Render y plan Flutter", "Subtitle"),
        grid(
            ["Elemento", "Estado documentado"],
            [
                ["Repositorio", "BastianMaltexco/Mantencion_Reportes - rama main"],
                ["Commit de referencia", "e3cfc6a - Prepare Render deployment with Azure SQL"],
                ["Aplicación", "Flask modular con SQLAlchemy y pyodbc"],
                ["Base de pruebas", "Azure SQL Database ReportesMantencionTest, Brasil South"],
                ["API móvil", "API REST /api/v1 con JWT y refresh tokens revocables"],
                ["Fecha de esta bitácora", "14 de septiembre de 2026"],
            ],
            [4.4 * cm, 11.8 * cm],
        ),
        Spacer(1, 18),
        p("Propósito", "H2Custom"),
        p("Este documento reúne las decisiones, scripts, incidencias resueltas y procedimientos relevantes realizados durante la construcción de la plataforma. No contiene contraseñas, tokens, cadenas completas de conexión ni otros secretos."),
        p("Actualización futura", "H2Custom"),
        p("El archivo se genera con <font name='Courier'>scripts/generate_project_history_pdf.py</font>. Al implementar cambios relevantes, se debe actualizar esta bitácora y regenerar el PDF con el mismo nombre. Los valores sensibles deben permanecer fuera del documento."),
        PageBreak(),
    ])

    flow.extend(section("1. Resumen de la solución"))
    flow.append(p("La plataforma registra trabajos de mantención en terreno para Maltexco. Dispone de autenticación por usuario y rol, captura de reportes, checklist, evidencia fotográfica, adjuntos, historial, dashboard, carga de petróleo de dos generadores, catálogos de área-sección-maquinaria y despliegue preparado para Azure SQL y Render."))
    flow.append(grid(
        ["Capa", "Tecnología y responsabilidad"],
        [
            ["Frontend web", "HTML semántico, Jinja, Tailwind CSS CDN, JavaScript ES6 y Chart.js."],
            ["Backend", "Python Flask con Application Factory y Blueprints: auth y reports."],
            ["Persistencia", "SQL Server local y Azure SQL Database mediante SQLAlchemy + pyodbc."],
            ["Archivos", "Carpeta uploads local. En Render es temporal; para producción se recomienda Azure Blob Storage."],
            ["Producción", "Docker Debian 12, Microsoft ODBC Driver 18, Gunicorn y Render."],
            ["Móvil futuro", "Flutter Android/iOS, API HTTPS Flask, sin acceso directo a Azure SQL."],
        ],
        [3.1 * cm, 13.1 * cm],
    ))
    flow.append(p("Estructura principal", "H2Custom"))
    flow.append(code("""app/
  __init__.py       Application Factory, seguridad de sesión y health check
  auth.py           Login, logout y administración de usuarios
  api.py            API REST v1, JWT, refresh tokens y control de roles
  reports.py        Reportes, checklist, petróleo, catálogos y adjuntos
  models.py         Modelos SQLAlchemy
  templates/        Vistas HTML/Jinja
scripts/            Migración Azure y generación de esta bitácora
script_db.sql       DDL base SQL Server
render.yaml         Blueprint de Render
Dockerfile          Imagen Linux con ODBC 18 y Gunicorn"""))

    flow.extend(section("2. Cronología de implementación"))
    flow.append(grid(
        ["Etapa", "Acción realizada y resultado"],
        [
            ["1. Base inicial", "Se definió Flask modular, autenticación, roles, reportes, adjuntos y base SQL Server ReportesMantencion."],
            ["2. Corrección DDL", "Se detectó que dbo.Usuarios usa IdUsuario, no UsuarioId. Se corrigieron las claves foráneas y se creó Reportes antes de Adjuntos."],
            ["3. Ejecución local", "Se resolvió el error de ejecución desde C:\\WINDOWS\\system32 usando el directorio del proyecto, entorno virtual y archivo .env."],
            ["4. Usuarios", "Se aclaró que usuarios de SQL Server y usuarios de la aplicación son distintos. La app usa dbo.Usuarios con hash de contraseña."],
            ["5. Reporte web", "Se incorporaron validaciones CSRF, carga múltiple, sellado CreadoEn, historial, detalle e impresión."],
            ["6. Catálogos", "Se importaron área, sección y maquinaria desde hoja Concat; se creó la vista vw_AreaSeccionMaquinaria."],
            ["7. Checklist", "Se añadieron preguntas, respuestas Si/No/No aplica y reglas de evidencia fotográfica según respuesta."],
            ["8. Fechas", "Se agregaron comienzo y finalización de tarea con DATETIMEOFFSET. Ubicación pasó a ser opcional."],
            ["9. Petróleo", "Se añadió formulario de carga para Generador 1 y 2, límites de litros, horómetro y cuatro fotos obligatorias."],
            ["10. Dashboard", "Se incorporaron filtros, métricas y vista para reportes de mantención y cargas de petróleo."],
            ["11. GitHub", "Se protegieron .env, uploads y archivos sensibles; se inicializó y publicó el repositorio."],
            ["12. Azure", "Se creó la base gratuita de pruebas en Brasil South y se migró esquema y datos desde SQL Server local."],
            ["13. Render", "Se preparó Docker, ODBC 18, Gunicorn, render.yaml, health check y variables de entorno seguras."],
            ["14. Móvil", "Se analizó una futura app Flutter offline-first apoyada por una API REST Flask independiente."],
            ["15. API móvil v1", "Se implementaron etapas 1-2: contrato OpenAPI, autenticación JWT, refresh tokens rotativos, roles, errores uniformes y pruebas."],
            ["16. API catálogos y registros", "Se implementaron etapas 3-4: catálogos, historial paginado, creación de mantención/checklist y carga de petróleo con reglas compartidas."],
        ],
        [3.1 * cm, 13.1 * cm],
    ))

    flow.extend(section("3. Base de datos SQL Server y Azure SQL"))
    flow.append(p("La base original se denomina <font name='Courier'>ReportesMantencion</font>. La réplica de pruebas en Azure se denomina <font name='Courier'>ReportesMantencionTest</font>. La migración se ejecutó sin modificar ni eliminar datos del origen."))
    flow.append(p("Tablas principales", "H2Custom"))
    flow.append(grid(
        ["Tabla", "Uso"],
        [
            ["Roles", "Roles Administrador y Técnico."],
            ["Usuarios", "Nombre, correo, hash de contraseña, rol, activo y fechas."],
            ["Reportes", "Reporte de mantención, técnico, cliente, servicio, tarea, catálogos y sello de creación."],
            ["Adjuntos", "Metadatos de archivos generales y de evidencia."],
            ["ReporteChecklist", "Respuesta y adjunto de evidencia por pregunta."],
            ["Areas", "Catálogo de áreas activas."],
            ["Secciones", "Secciones asociadas a un área."],
            ["Maquinarias", "Maquinarias asociadas a una sección y código de origen."],
            ["CargasPetroleoGeneradores", "Cabecera de carga de petróleo."],
            ["CargasPetroleoGeneradorDetalle", "Litros, horómetro y fotos de agua/aceite por generador."],
            ["ReportesDiarios", "Tabla heredada existente; no es usada por los formularios principales actuales."],
            ["ApiRefreshTokens", "Hash HMAC, emisión, expiración, revocación y rotación de refresh tokens móviles."],
        ],
        [5.2 * cm, 11.0 * cm],
    ))
    flow.append(p("Relaciones esenciales", "H2Custom"))
    flow.append(code("""Usuarios 1 - N Reportes
Reportes 1 - N Adjuntos
Reportes 1 - N ReporteChecklist
Areas 1 - N Secciones 1 - N Maquinarias
Usuarios 1 - N CargasPetroleoGeneradores
CargasPetroleoGeneradores 1 - N CargasPetroleoGeneradorDetalle"""))
    flow.append(p("Integridad aplicada", "H2Custom"))
    flow.append(bullet([
        "Claves primarias, claves foráneas e índices para fecha, cliente, técnico, catálogo y adjuntos.",
        "Restricciones CHECK para servicio, respuestas de checklist, tamaño de archivo, litros menores a 750, horómetro y número de generador.",
        "Tipos DATETIMEOFFSET(7) para sellos y tiempos de tarea/carga donde corresponde.",
        "La vista dbo.vw_AreaSeccionMaquinaria une los tres catálogos para consulta." ,
    ]))

    flow.extend(section("4. Scripts SQL y orden de ejecución"))
    flow.append(grid(
        ["Archivo", "Propósito"],
        [
            ["script_db.sql", "Crea Roles, Usuarios, Reportes, Adjuntos, relaciones e índices iniciales."],
            ["script_catalogos_area_seccion_maquinaria.sql", "Crea e importa Areas, Secciones, Maquinarias y la vista consolidada."],
            ["migracion_reportes_catalogos.sql", "Agrega AreaId, SeccionId y MaquinariaId a Reportes, FK e índices."],
            ["migracion_checklist_reportes.sql", "Crea ReporteChecklist, validación de respuesta, FK e índice."],
            ["migracion_fechas_tarea.sql", "Agrega ComienzoTarea y FinalizacionTarea."],
            ["migracion_ubicacion_opcional.sql", "Permite NULL en Ubicacion."],
            ["migracion_carga_petroleo.sql", "Crea cabecera y detalle de carga de petróleo."],
            ["migracion_api_refresh_tokens.sql", "Crea almacenamiento aditivo y revocable de refresh tokens para /api/v1."],
            ["diagnostico_usuarios.sql", "Consulta diagnóstica para revisar la estructura de usuarios."],
        ],
        [6.2 * cm, 10.0 * cm],
    ))
    flow.append(p("Ejemplo seguro de creación de usuario de aplicación", "H2Custom"))
    flow.append(p("La forma recomendada es usar el panel Administrador de la aplicación, ya que Flask genera el hash con Werkzeug. Nunca se debe guardar la contraseña en texto plano en dbo.Usuarios."))
    flow.append(code("""# La aplicación ejecuta el equivalente lógico:
password_hash = generate_password_hash(password)
User(username=correo, full_name=nombre,
     password_hash=password_hash, role=rol, is_active=True)"""))
    flow.append(p("Incidencias SQL resueltas", "H2Custom"))
    flow.append(bullet([
        "La FK inicial apuntaba a Usuarios.UsuarioId, pero la columna real es Usuarios.IdUsuario.",
        "Adjuntos no podía referenciar Reportes hasta que Reportes existiera correctamente.",
        "La importación de maquinaria detectó duplicados; la carga se ajustó para conservar los datos válidos y la unicidad requerida.",
        "Las restricciones se escribieron con bloques IF/EXEC correctos para evitar errores de sintaxis de ALTER TABLE.",
    ]))

    flow.extend(section("5. Backend Flask y reglas de negocio"))
    flow.append(grid(
        ["Componente", "Responsabilidad actual"],
        [
            ["app/__init__.py", "Factory, SQLAlchemy, CSRF web, login_required, admin_required, bootstrap de administrador y /healthz."],
            ["app/auth.py", "Login/logout web, alta, edición y activación/desactivación de usuarios."],
            ["app/api.py", "Blueprint /api/v1: JSON, tokens, renovación, logout y autorización por rol."],
            ["app/reports.py", "Historial, filtros, dashboard, mantención, checklist, petróleo, catálogos, detalle e adjuntos."],
            ["app/models.py", "Mapeo SQLAlchemy de tablas dbo con nombres existentes."],
            ["config.py", "Carga .env local o ENV_FILE alternativo, URI SQLAlchemy, TLS Azure y carpeta de subida."],
        ],
        [4.4 * cm, 11.8 * cm],
    ))
    flow.append(p("Autenticación y usuarios", "H2Custom"))
    flow.append(bullet([
        "Login web mediante correo/usuario y hash Werkzeug check_password_hash.",
        "Sesión web firmada con Flask, token CSRF para solicitudes con cambio de estado y roles Administrador/Técnico.",
        "El usuario administrador inicial se puede crear desde ADMIN_USERNAME y ADMIN_PASSWORD si la tabla contiene el rol y el usuario no existe.",
        "Las credenciales de SQL Server no son usuarios de la aplicación. Los usuarios de la app viven en dbo.Usuarios.",
    ]))
    flow.append(p("Reporte de mantención", "H2Custom"))
    flow.append(bullet([
        "Campos: comienzo, finalización, área, sección, maquinaria, tipo de servicio, cliente y observaciones.",
        "La selección de maquinaria se valida en servidor para confirmar la jerarquía área-sección-maquinaria activa.",
        "CreadoEn se asigna en servidor y no proviene del formulario.",
        "Adjuntos permitidos: JPG, JPEG, PNG, PDF, DOC, DOCX, XLS y XLSX.",
    ]))
    flow.append(p("Checklist de entrega", "H2Custom"))
    flow.append(grid(
        ["Pregunta", "Evidencia obligatoria"],
        [
            ["Libre de elementos que pueden obstruir el trabajo", "JPG/PNG si la respuesta es No."],
            ["Piezas o componentes en mal estado", "JPG/PNG si la respuesta es Si."],
            ["Problema o falla es constante", "No obligatoria."],
            ["Entrega de equipo energizado", "No obligatoria."],
            ["Zona de trabajo limpia", "JPG/PNG si la respuesta es Si."],
            ["Problema o falla solucionada", "No obligatoria."],
            ["Protecciones instaladas", "No obligatoria."],
        ],
        [9.0 * cm, 7.2 * cm],
    ))
    flow.append(p("Carga de petróleo", "H2Custom"))
    flow.append(bullet([
        "Fecha y hora de carga obligatoria, dos generadores y observaciones generales.",
        "Litros permitidos: 0 a 749. Horómetro mayor o igual a cero.",
        "Para cada generador son obligatorias fotografías JPG/PNG de nivel de agua y nivel de aceite.",
    ]))

    flow.extend(section("6. Ejecución local, configuración y diagnóstico"))
    flow.append(p("La aplicación se ejecuta desde la carpeta del proyecto. El error inicial de run.py ocurrió porque PowerShell estaba en C:\\WINDOWS\\system32, donde no existía el archivo."))
    flow.append(code("""cd "C:\\Users\\Bastian\\Documents\\ChatGPT\\Reportes 2.0"
.\\.venv\\Scripts\\Activate.ps1
py run.py

# Abrir: http://127.0.0.1:5000"""))
    flow.append(p("Variables locales", "H2Custom"))
    flow.append(grid(
        ["Grupo", "Variables"],
        [
            ["Base de datos", "DB_SERVER, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, DB_DRIVER."],
            ["Cifrado", "DB_ENCRYPT y DB_TRUST_SERVER_CERTIFICATE. Local: no/yes. Azure: yes/no."],
            ["Aplicación", "SECRET_KEY, UPLOAD_FOLDER, MAX_CONTENT_LENGTH, SESSION_COOKIE_SECURE."],
            ["Administrador inicial", "ADMIN_USERNAME y ADMIN_PASSWORD."],
            ["API móvil", "API_TOKEN_SECRET, API_TOKEN_ISSUER, API_ACCESS_TOKEN_MINUTES y API_REFRESH_TOKEN_DAYS."],
            ["Entorno alternativo", "ENV_FILE=.env.azure-test para conectar temporalmente a Azure."],
        ],
        [4.7 * cm, 11.5 * cm],
    ))
    flow.append(p("Buenas prácticas", "H2Custom"))
    flow.append(bullet([
        "No publicar .env, .env.azure-test, uploads ni claves. .gitignore y .dockerignore los excluyen.",
        "No usar DATABASE_URL si se utilizan las variables DB_* separadas.",
        "Mantener el .env local para SQL Server y usar ENV_FILE solamente para la prueba Azure.",
        "El error ZoneInfo America/Santiago se evitó usando la zona local disponible del sistema para convertir los valores de tarea.",
    ]))

    flow.extend(section("7. Azure SQL Database"))
    flow.append(p("Objetivo: disponer de una copia de pruebas pública sin modificar ni exponer el SQL Server local."))
    flow.append(grid(
        ["Recurso", "Resultado"],
        [
            ["Suscripción", "Azure subscription 1, Enabled."],
            ["Resource Group", "rg-reportes-mantencion-test-cl."],
            ["Primer intento", "Chile Central rechazó Free Offer para el objetivo solicitado. Se mantuvo el servidor intacto y no se creó base facturable."],
            ["Servidor de prueba", "sql-reportesmant-brs9284.database.windows.net."],
            ["Región", "Brazil South."],
            ["Base", "ReportesMantencionTest."],
            ["SKU", "General Purpose Serverless GP_S_Gen5_2, capacidad 2 Gen5, máximo 32 GiB."],
            ["Límite gratuito", "Creada con --use-free-limit y freeLimitExhaustionBehavior=AutoPause."],
        ],
        [4.9 * cm, 11.3 * cm],
    ))
    flow.append(p("Secuencia aplicada", "H2Custom"))
    flow.append(bullet([
        "Se validó la suscripción activa y se registró el proveedor Microsoft.Sql.",
        "Se creó el Resource Group exclusivo de pruebas.",
        "Chile Central no aceptó la oferta gratuita y se detuvo, sin usar BillOverUsage.",
        "Con autorización se creó el servidor en Brazil South y la base con AutoPause.",
        "Se creó una regla de firewall temporal para una sola IP pública local y se probó conexión cifrada ODBC 18.",
        "No se abrió ni modificó el SQL Server local para Internet.",
    ]))
    flow.append(p("Migración", "H2Custom"))
    flow.append(bullet([
        "Se auditó el origen: no había procedimientos, triggers, funciones, dependencias entre bases, FileStream, memoria en línea ni Full Text.",
        "Se creó scripts/migrate_sqlserver_to_azure.py. Por defecto solo audita; --apply migra a un destino vacío.",
        "Se preservaron valores IDENTITY, tablas, PK, FK, defaults, índices, datos y vista dbo.vw_AreaSeccionMaquinaria.",
        "SQLAlchemy reflejó los índices únicos correctamente; las nueve restricciones CHECK se añadieron y validaron de forma explícita.",
        "Origen y destino finalizaron con 11 tablas, 1 vista, 11 PK, 12 FK, 9 CHECK, 12 defaults y 8 índices únicos; los conteos de filas coincidieron.",
    ]))
    flow.append(p("Nota sobre adjuntos", "H2Custom"))
    flow.append(p("Se migraron los metadatos de dbo.Adjuntos. Los archivos físicos permanecen en uploads local, porque Azure SQL almacena metadatos y no archivos binarios."))

    flow.extend(section("8. GitHub y preparación Render"))
    flow.append(grid(
        ["Archivo", "Función"],
        [
            [".gitignore", "Excluye .env, variaciones .env.*, entornos virtuales, node_modules, cargas y llaves."],
            [".dockerignore", "Evita que secretos, cargas y archivos locales entren a la imagen Docker."],
            ["Dockerfile", "Python 3.13 Debian 12, msodbcsql18, unixODBC, pyodbc y Gunicorn."],
            ["render.yaml", "Blueprint Web Service Docker, plan free, autoDeploy false, health check y variables sin secretos."],
            ["wsgi.py", "Expone app para Gunicorn."],
            ["requirements.txt", "Incluye Flask, SQLAlchemy, pyodbc, PyJWT, pytest, dotenv, Waitress y Gunicorn."],
        ],
        [4.5 * cm, 11.7 * cm],
    ))
    flow.append(p("Comando de producción", "H2Custom"))
    flow.append(code("""gunicorn --bind 0.0.0.0:${PORT:-10000} \\
  --workers ${WEB_CONCURRENCY:-2} --timeout 120 \\
  --access-logfile - --error-logfile - wsgi:app"""))
    flow.append(p("Render y archivos", "H2Custom"))
    flow.append(bullet([
        "Para pruebas, UPLOAD_FOLDER=/tmp/reportes-uploads. Es almacenamiento efímero y se pierde en reinicio, redeploy o suspensión del servicio gratuito.",
        "Para producción se recomienda Azure Blob Storage. Un disco persistente de Render también sirve, pero requiere un plan pagado y limita el escalado.",
        "Antes de desplegar se requiere una regla de firewall de Azure SQL para la salida de Render. La regla de migración solo permite la IP local temporal.",
        "SECRET_KEY se genera en Render. DB_USER y DB_PASSWORD se agregan manualmente como secretos y nunca se escriben en render.yaml.",
        "API_TOKEN_SECRET también debe configurarse manualmente en Render y ser distinto de SECRET_KEY.",
    ]))
    flow.append(p("Historial Git", "H2Custom"))
    flow.append(code("""63bf740  Initial commit: field reporting application
e3cfc6a  Prepare Render deployment with Azure SQL

Repositorio: https://github.com/BastianMaltexco/Mantencion_Reportes"""))

    flow.extend(section("9. API móvil Flask v1 y plan Flutter"))
    flow.append(p("La aplicación móvil no debe conectarse a Azure SQL. Debe comunicarse exclusivamente con una API HTTPS de Flask, versionada bajo /api/v1 y separada de las rutas HTML actuales. Las etapas 1 y 2 ya están implementadas, probadas localmente y verificadas contra ReportesMantencionTest."))
    flow.append(p("Contrato e implementación actual", "H2Custom"))
    flow.append(grid(
        ["Recurso", "Estado y comportamiento"],
        [
            ["docs/API_V1_CONTRACT.md", "Contrato humano: convenciones, errores, seguridad, ejemplos y límites de esta etapa."],
            ["docs/openapi-v1.yaml", "Especificación OpenAPI 3.0.3 para integración y clientes móviles."],
            ["GET /api/v1/health", "Estado público de API v1."],
            ["POST /auth/login", "Autentica contra dbo.Usuarios y emite access JWT + refresh opaco."],
            ["POST /auth/refresh", "Rota el refresh token; el anterior queda revocado inmediatamente."],
            ["POST /auth/logout", "Revocación idempotente de refresh token."],
            ["GET /auth/me", "Perfil mediante Authorization: Bearer access token."],
            ["GET /admin/status", "Ejemplo de endpoint protegido por el rol Administrador."],
            ["GET /areas, /sections, /machineries", "Catálogos activos encadenados por área y sección."],
            ["GET/POST /reports y GET /reports/{id}", "Historial paginado, filtros, detalle, checklist y creación validada."],
            ["GET/POST /fuel-loads y GET /fuel-loads/{id}", "Historial, detalle y creación de carga para ambos generadores."],
        ],
        [5.2 * cm, 11.0 * cm],
    ))
    flow.append(p("Seguridad y errores", "H2Custom"))
    flow.append(bullet([
        "Access JWT HS256 de 15 minutos por defecto; los claims incluyen subject, rol, emisor, emisión, expiración, identificador y tipo.",
        "Refresh token aleatorio de 30 días por defecto. Solo se guarda su HMAC-SHA256, nunca el token original.",
        "El access token conserva una vida limitada tras logout; el refresh queda revocado al instante. Usuarios inactivos no pueden iniciar, renovar ni acceder.",
        "Todos los errores API usan error.code, error.message, details opcional y request_id; 404 y 405 de /api/v1 también responden JSON.",
        "La API no usa la cookie web ni CSRF. La web conserva sesión y CSRF sin cambios.",
        "Técnicos solo pueden consultar sus propios reportes y cargas; Administrador puede consultar todos y filtrar por técnico.",
    ]))
    flow.append(p("Pruebas ejecutadas", "H2Custom"))
    flow.append(bullet([
        "pytest: autenticación, errores, roles, catálogos, filtros, paginación, checklist/evidencias, petróleo y regresión web. Resultado: 5 pruebas aprobadas.",
        "Integración Azure: login 200; catálogos 200; POST/GET/detalle de reportes 201/200/200; POST/GET/detalle de petróleo 201/200/200; web login/dashboard 302/200.",
        "La tabla dbo.ApiRefreshTokens y su índice IX_ApiRefreshTokens_Usuario_Expira fueron creados en Azure con la migración aditiva.",
    ]))
    flow.append(p("Reglas de creación implementadas", "H2Custom"))
    flow.append(bullet([
        "POST /reports acepta JSON sin archivos o multipart con payload JSON, evidencias evidence_<clave> y adjuntos generales. El checklist completo de siete preguntas es obligatorio.",
        "Se reutiliza el mismo servicio de dominio de la web: jerarquía activa área-sección-maquinaria, orden de fechas, servicio permitido y evidencia condicional.",
        "POST /fuel-loads usa multipart con payload JSON y water_1, oil_1, water_2, oil_2. Limita estrictamente litros a valores desde 0 hasta menos de 750.",
        "Por ahora los archivos permanecen bajo UPLOAD_FOLDER. Azure Blob Storage y descargas API siguen pendientes de la etapa dedicada a adjuntos.",
    ]))
    flow.append(p("Endpoints planificados para etapas posteriores", "H2Custom"))
    flow.append(grid(
        ["Dominio", "Endpoints REST sugeridos"],
        [
            ["Autenticación", "POST /auth/login, POST /auth/refresh, POST /auth/logout, GET /me."],
            ["Usuarios", "GET/POST /users, PATCH /users/{id}, PATCH /users/{id}/status para administrador."],
            ["Catálogos", "GET /areas, /sections?area_id=, /machineries?section_id= y /catalogs/sync?since=."],
            ["Reportes", "GET /reports, POST /reports, GET/PATCH /reports/{id}, POST /reports/{id}/submit."],
            ["Archivos", "POST /reports/{id}/attachments, GET /attachments/{id}, DELETE en borrador."],
            ["Petróleo", "GET/POST /fuel-loads y GET /fuel-loads/{id}."],
            ["Dashboard/sync", "GET /dashboard/summary, GET /sync/pull?cursor= y POST /sync/push."],
        ],
        [4.5 * cm, 11.7 * cm],
    ))
    flow.append(p("Autenticación móvil", "H2Custom"))
    flow.append(bullet([
        "Access token JWT de corta duración y refresh token rotativo, revocable y guardado hasheado ya implementados en dbo.ApiRefreshTokens.",
        "Authorization: Bearer token. Los tokens se guardan en Keychain/Keystore, nunca en SQLite ni preferencias normales.",
        "La web mantiene cookies y CSRF. La API móvil usa decoradores de token y autorización por rol sin modificar la web.",
    ]))
    flow.append(p("Edición y auditoría", "H2Custom"))
    flow.append(p("La web actual crea reportes pero no los edita. Para móvil se propone ciclo Borrador - Enviado: solo los borradores son editables; al enviar se validan checklist y archivos y se bloquea el registro. Una corrección posterior debe ser una revisión vinculada, no una modificación silenciosa del sello original."))
    flow.append(p("Offline y sincronización", "H2Custom"))
    flow.append(bullet([
        "Base SQLite local con catálogos, reportes recientes, borradores, checklist, metadatos de adjuntos y cola pending_operations.",
        "Cada operación usa ClienteRequestId UUID para idempotencia y evitar duplicados después de reintentos.",
        "Fotos capturadas se copian a almacenamiento permanente de la app antes de sincronizar, porque la caché de cámara puede eliminarse.",
        "Errores de red, timeout, 429 y 5xx reintentan con espera exponencial; 400/422 se bloquean para corrección; 409 exige resolver conflicto; 401 intenta refresh una vez.",
        "Sincronizar en apertura, al recuperar red y con trabajo de fondo de mejor esfuerzo. iOS puede postergar tareas en background.",
    ]))
    flow.append(p("Arquitectura Flutter", "H2Custom"))
    flow.append(code("""lib/
  app/        app.dart, router.dart, theme.dart
  core/       api, auth, database, errors, network, sync, storage
  features/   auth, catalog, reports, fuel_loads, dashboard, users, sync_center

Cada feature: data/ - domain/ - presentation/"""))
    flow.append(grid(
        ["Paquete", "Uso previsto"],
        [
            ["flutter_riverpod", "Estado, dependencias, asincronía y pruebas."],
            ["go_router", "Navegación."],
            ["dio", "HTTPS, interceptores, refresh y multipart."],
            ["flutter_secure_storage", "Tokens en Keystore/Keychain."],
            ["drift + drift_flutter", "SQLite tipado y reactivo offline."],
            ["connectivity_plus", "Disparador de sincronización, no garantía de Internet."],
            ["workmanager", "Sincronización de mejor esfuerzo en Android/iOS."],
            ["image_picker + file_picker", "Cámara, galería y documentos."],
            ["path_provider + uuid", "Archivos persistentes y claves de idempotencia."],
        ],
        [5.0 * cm, 11.2 * cm],
    ))

    flow.extend(section("10. Lista de verificación operativa"))
    flow.append(bullet([
        "Antes de cambiar DDL: respaldar, revisar el script y ejecutar primero en la base de pruebas Azure.",
        "Antes de desplegar Render: configurar los secretos DB_*, SECRET_KEY, TLS y la regla de firewall Azure para Render.",
        "Antes de producción: sustituir uploads efímero por Azure Blob Storage o almacenamiento persistente con política de respaldo.",
        "Antes de crear la app móvil: extender el contrato OpenAPI para catálogos, borradores, revisiones, checklist, archivos e historial.",
        "Tras cada hito: actualizar scripts, README, esta bitácora y ejecutar pruebas locales/Azure." ,
        "Nunca incluir en GitHub: .env, .env.azure-test, tokens, contraseñas, llaves, archivos subidos ni backups de base de datos.",
    ]))
    flow.append(p("Comandos de referencia", "H2Custom"))
    flow.append(code("""# Local con SQL Server original
py run.py

# Local temporal contra Azure SQL
$env:ENV_FILE = ".env.azure-test"
py run.py
Remove-Item Env:ENV_FILE -ErrorAction SilentlyContinue

# Auditoría/migración Azure (usar solo destino vacío)
py scripts/migrate_sqlserver_to_azure.py
py scripts/migrate_sqlserver_to_azure.py --apply

# Regenerar esta bitácora
py scripts/generate_project_history_pdf.py"""))
    flow.append(Spacer(1, 12))
    flow.append(p("Fin de la bitácora", "H2Custom"))
    flow.append(p("Documento generado sin secretos. Para información viva, el código versionado y los scripts SQL del repositorio son la fuente operativa principal.", "Small"))
    return flow


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc = BaseDocTemplate(
        str(OUTPUT), pagesize=A4,
        leftMargin=1.55 * cm, rightMargin=1.55 * cm,
        topMargin=1.55 * cm, bottomMargin=1.65 * cm,
        title="Reportes Mantención - Bitácora técnica",
        author="Bastian Maltexco",
    )
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="normal")
    doc.addPageTemplates([PageTemplate(id="all", frames=[frame], onPage=footer)])
    doc.build(story())
    print(OUTPUT)


if __name__ == "__main__":
    main()
