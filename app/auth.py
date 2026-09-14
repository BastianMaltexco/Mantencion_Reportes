from urllib.parse import urljoin, urlparse

from flask import Blueprint, flash, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

from app import admin_required, db, login_required
from app.models import Role, User

auth_bp = Blueprint("auth", __name__, url_prefix="/auth")


def _safe_redirect(target):
    base = urlparse(request.host_url)
    candidate = urlparse(urljoin(request.host_url, target or ""))
    return candidate.scheme in {"http", "https"} and candidate.netloc == base.netloc


@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    if session.get("user_id"):
        return redirect(url_for("reports.dashboard"))
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        user = db.session.execute(db.select(User).where(User.username == username)).scalar_one_or_none()
        if user and user.is_active and check_password_hash(user.password_hash, password):
            session.clear()
            session.update(user_id=user.id, user_name=user.full_name, role=user.role)
            # Tras autenticar se entrega siempre el panel principal. Esto evita que
            # parámetros `next` heredados o mal formados terminen en una ruta 404.
            return redirect(url_for("reports.dashboard"))
        flash("Credenciales inválidas o usuario desactivado.", "error")
    return render_template("login.html")


@auth_bp.post("/logout")
@login_required
def logout():
    session.clear()
    flash("Sesión cerrada correctamente.", "success")
    return redirect(url_for("auth.login"))


@auth_bp.route("/users", methods=["GET", "POST"])
@admin_required
def users():
    roles = db.session.execute(db.select(Role).order_by(Role.name)).scalars().all()
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        full_name = request.form.get("full_name", "").strip()
        password = request.form.get("password", "")
        role_name = request.form.get("role", "")
        if not username or not full_name or len(password) < 10 or not role_name:
            flash("Complete todos los campos; la contraseña debe tener al menos 10 caracteres.", "error")
        elif db.session.execute(db.select(User).where(User.username == username)).scalar_one_or_none():
            flash("Ese nombre de usuario ya existe.", "error")
        elif not db.session.execute(db.select(Role).where(Role.name == role_name)).scalar_one_or_none():
            flash("El rol seleccionado no es válido.", "error")
        else:
            db.session.add(User(username=username, full_name=full_name, password_hash=generate_password_hash(password), role=role_name))
            db.session.commit()
            flash("Usuario creado.", "success")
            return redirect(url_for("auth.users"))
    all_users = db.session.execute(db.select(User).order_by(User.full_name)).scalars().all()
    return render_template("users.html", users=all_users, roles=roles)


@auth_bp.route("/users/<int:user_id>/edit", methods=["GET", "POST"])
@admin_required
def edit_user(user_id):
    user = db.get_or_404(User, user_id)
    roles = db.session.execute(db.select(Role).order_by(Role.name)).scalars().all()
    if request.method == "POST":
        user.full_name = request.form.get("full_name", "").strip()
        user.username = request.form.get("username", "").strip()
        user.role = request.form.get("role", "")
        password = request.form.get("password", "")
        if not user.full_name or not user.username or not db.session.execute(db.select(Role).where(Role.name == user.role)).scalar_one_or_none():
            flash("Complete los datos requeridos.", "error")
        elif password and len(password) < 10:
            flash("La nueva contraseña debe tener al menos 10 caracteres.", "error")
        elif (duplicate := db.session.execute(db.select(User).where(User.username == user.username, User.id != user.id)).scalar_one_or_none()):
            flash("Ese nombre de usuario ya existe.", "error")
        else:
            if password:
                user.password_hash = generate_password_hash(password)
            db.session.commit()
            flash("Usuario actualizado.", "success")
            return redirect(url_for("auth.users"))
    return render_template("user_edit.html", user=user, roles=roles)


@auth_bp.post("/users/<int:user_id>/toggle")
@admin_required
def toggle_user(user_id):
    user = db.get_or_404(User, user_id)
    if user.id == session["user_id"]:
        flash("No puede desactivar su propia cuenta.", "error")
    else:
        user.is_active = not user.is_active
        db.session.commit()
        flash("Estado de usuario actualizado.", "success")
    return redirect(url_for("auth.users"))
