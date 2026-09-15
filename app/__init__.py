from datetime import datetime, timezone
from functools import wraps
from pathlib import Path
import secrets

from flask import Flask, abort, flash, redirect, request, session, url_for
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import text
from werkzeug.security import generate_password_hash

from config import Config

db = SQLAlchemy()


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("user_id"):
            flash("Inicie sesión para continuar.", "warning")
            return redirect(url_for("auth.login", next=request.full_path))
        return view(*args, **kwargs)
    return wrapped


def admin_required(view):
    @wraps(view)
    @login_required
    def wrapped(*args, **kwargs):
        if session.get("role") != "Administrador":
            abort(403)
        return view(*args, **kwargs)
    return wrapped


def csrf_token():
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_urlsafe(32)
    return session["csrf_token"]


def validate_csrf():
    # La API móvil no utiliza cookies de sesión: se autentica exclusivamente
    # mediante Authorization: Bearer. Por ello no corresponde exigirle CSRF.
    if request.path.startswith("/api/"):
        return None
    if request.method in {"POST", "PUT", "PATCH", "DELETE"}:
        token = request.form.get("csrf_token", "")
        if not token or not secrets.compare_digest(token, session.get("csrf_token", "")):
            # Una sesión puede quedar obsoleta tras reiniciar el servidor local
            # o cambiar SECRET_KEY. No se procesa el POST; se renueva de forma segura.
            session.clear()
            flash("La sesión se actualizó. Intente iniciar sesión nuevamente.", "warning")
            return redirect(url_for("auth.login"))


def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)
    if not app.config["SQLALCHEMY_DATABASE_URI"]:
        raise RuntimeError("Falta DATABASE_URL. Cree .env desde .env.example.")
    Path(app.config["UPLOAD_FOLDER"]).mkdir(parents=True, exist_ok=True)
    db.init_app(app)

    app.jinja_env.globals["csrf_token"] = csrf_token
    app.jinja_env.globals["utcnow"] = lambda: datetime.now(timezone.utc)
    app.before_request(validate_csrf)

    from app.auth import auth_bp
    from app.api import api_bp, api_error_response
    from app.reports import reports_bp
    app.register_blueprint(auth_bp)
    app.register_blueprint(api_bp)
    app.register_blueprint(reports_bp)

    @app.template_filter("localdatetime")
    def localdatetime(value):
        if not value:
            return "—"
        return value.strftime("%d-%m-%Y %H:%M %z")

    @app.errorhandler(403)
    def forbidden(_error):
        if request.path.startswith("/api/v1/"):
            return api_error_response(403, "forbidden", "No tiene permiso para esta operación.")
        return "Acceso no autorizado.", 403

    @app.errorhandler(404)
    def not_found(error):
        if request.path.startswith("/api/v1/"):
            return api_error_response(404, "not_found", "El recurso solicitado no existe.")
        return error

    @app.errorhandler(405)
    def method_not_allowed(error):
        if request.path.startswith("/api/v1/"):
            return api_error_response(405, "method_not_allowed", "El método HTTP no está permitido.")
        return error

    @app.errorhandler(413)
    def too_large(_error):
        flash("Los archivos exceden el límite permitido de 25 MB por reporte.", "error")
        return redirect(request.referrer or url_for("reports.create_report"))

    @app.get("/healthz")
    def healthz():
        """Sonda liviana de Render; no requiere autenticación ni expone datos."""
        return {"status": "ok"}, 200

    with app.app_context():
        # El esquema de produccion se aplica con script_db.sql. Esto facilita la primera prueba local.
        bootstrap_admin(app)
    return app


def bootstrap_admin(app):
    """Crea el admin inicial solo si las tablas ya fueron creadas por script_db.sql."""
    from app.models import Role, User
    try:
        admin_role = db.session.execute(db.select(Role).where(Role.name == "Administrador")).scalar_one_or_none()
        configured_admin = db.session.execute(
            db.select(User).where(User.username == app.config["ADMIN_USERNAME"])
        ).scalar_one_or_none()
        # Permite recuperar el acceso inicial aun cuando la tabla ya contenga usuarios heredados.
        if admin_role and not configured_admin:
            password = app.config.get("ADMIN_PASSWORD")
            if password:
                db.session.add(User(
                    username=app.config["ADMIN_USERNAME"], full_name="Administrador inicial",
                    password_hash=generate_password_hash(password), role=admin_role.name, is_active=True,
                ))
                db.session.commit()
    except Exception:
        db.session.rollback()  # La base puede no haber recibido aun el DDL.
