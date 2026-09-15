import os
from pathlib import Path
from sqlalchemy.engine import URL

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
# El archivo local del proyecto debe prevalecer sobre una variable heredada de Windows.
environment_file = Path(os.environ.get("ENV_FILE", BASE_DIR / ".env"))
if not environment_file.is_absolute():
    environment_file = BASE_DIR / environment_file
load_dotenv(environment_file, override=True)


class Config:
    """Configuracion comun. Las credenciales permanecen exclusivamente en .env."""

    SECRET_KEY = os.environ.get("SECRET_KEY", "solo-desarrollo-cambie-esta-clave")
    # Se admite una URL completa o variables separadas. La segunda opción evita
    # errores si la contraseña SQL contiene @, :, / u otros caracteres especiales.
    _db_server = os.environ.get("DB_SERVER")
    _db_user = os.environ.get("DB_USER")
    _db_password = os.environ.get("DB_PASSWORD")
    if _db_server and _db_user and _db_password:
        SQLALCHEMY_DATABASE_URI = URL.create(
            "mssql+pyodbc",
            username=_db_user,
            password=_db_password,
            host=_db_server,
            port=int(os.environ.get("DB_PORT", "1433")),
            database=os.environ.get("DB_NAME", "ReportesMantencion"),
            query={"driver": os.environ.get("DB_DRIVER", "ODBC Driver 18 for SQL Server"),
                   "TrustServerCertificate": os.environ.get("DB_TRUST_SERVER_CERTIFICATE", "yes"),
                   "Encrypt": os.environ.get("DB_ENCRYPT", "no")},
        )
    else:
        SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    # Evita reutilizar conexiones cerradas después de una pausa de Azure SQL Serverless.
    SQLALCHEMY_ENGINE_OPTIONS = {"pool_pre_ping": True, "pool_recycle": 1800}
    UPLOAD_FOLDER = Path(os.environ.get("UPLOAD_FOLDER", BASE_DIR / "uploads")).resolve()
    MAX_CONTENT_LENGTH = int(os.environ.get("MAX_CONTENT_LENGTH", 25 * 1024 * 1024))
    # Local mantiene los uploads existentes. Render debe usar azure_blob y
    # recibir su connection string exclusivamente como secreto del servicio.
    FILE_STORAGE_BACKEND = os.environ.get("FILE_STORAGE_BACKEND", "local")
    AZURE_STORAGE_CONNECTION_STRING = os.environ.get("AZURE_STORAGE_CONNECTION_STRING", "")
    AZURE_STORAGE_CONTAINER = os.environ.get("AZURE_STORAGE_CONTAINER", "reportes-adjuntos")
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    SESSION_COOKIE_SECURE = os.environ.get("SESSION_COOKIE_SECURE", "false").lower() == "true"
    ADMIN_USERNAME = os.environ.get("ADMIN_USERNAME", "admin")
    ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD")

    # API móvil: el secreto puede rotarse independientemente de las cookies web.
    # En producción API_TOKEN_SECRET debe definirse explícitamente y ser distinto
    # de SECRET_KEY. El fallback mantiene compatibles las instalaciones locales.
    API_TOKEN_SECRET = os.environ.get("API_TOKEN_SECRET", SECRET_KEY)
    API_TOKEN_ISSUER = os.environ.get("API_TOKEN_ISSUER", "reportes-mantencion-api")
    API_ACCESS_TOKEN_MINUTES = int(os.environ.get("API_ACCESS_TOKEN_MINUTES", "15"))
    API_REFRESH_TOKEN_DAYS = int(os.environ.get("API_REFRESH_TOKEN_DAYS", "30"))
