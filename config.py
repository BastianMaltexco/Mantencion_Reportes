import os
from pathlib import Path
from sqlalchemy.engine import URL

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
# El archivo local del proyecto debe prevalecer sobre una variable heredada de Windows.
load_dotenv(BASE_DIR / ".env", override=True)


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
                   "TrustServerCertificate": "yes", "Encrypt": "no"},
        )
    else:
        SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    UPLOAD_FOLDER = Path(os.environ.get("UPLOAD_FOLDER", BASE_DIR / "uploads")).resolve()
    MAX_CONTENT_LENGTH = int(os.environ.get("MAX_CONTENT_LENGTH", 25 * 1024 * 1024))
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    SESSION_COOKIE_SECURE = os.environ.get("SESSION_COOKIE_SECURE", "false").lower() == "true"
    ADMIN_USERNAME = os.environ.get("ADMIN_USERNAME", "admin")
    ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD")
