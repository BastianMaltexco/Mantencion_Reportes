"""API REST v1 para clientes móviles.

No comparte la sesión de la interfaz web. Todas las respuestas de error usan
el sobre definido en docs/API_V1_CONTRACT.md.
"""
from datetime import datetime, timedelta, timezone
from functools import wraps
import hashlib
import hmac
import json
import secrets
import uuid

import jwt
from flask import Blueprint, Response, current_app, g, jsonify, request, stream_with_context
from sqlalchemy import Date, String, cast, func, literal, select, union_all
from sqlalchemy.orm import joinedload
from werkzeug.security import check_password_hash

from app import db
from app.models import (
    ApiRefreshToken, Area, Attachment, FuelLoad, FuelLoadGenerator, Machinery,
    Report, ReportChecklist, Section, User,
)
from app.services.field_reports import BusinessRuleError, CHECKLIST, SERVICE_TYPES, create_fuel_load, create_maintenance_report
from app.services.storage import StorageError, get_file_storage, resolve_fuel_key, resolve_report_key


api_bp = Blueprint("api_v1", __name__, url_prefix="/api/v1")


class ApiError(Exception):
    def __init__(self, status, code, message, details=None):
        self.status = status
        self.code = code
        self.message = message
        self.details = details


def _utcnow():
    return datetime.now(timezone.utc)


def _as_utc(value):
    """Normaliza valores devueltos por drivers que omiten tzinfo en pruebas."""
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def api_error_response(status, code, message, details=None):
    request_id = g.get("request_id") or request.headers.get("X-Request-ID") or str(uuid.uuid4())
    payload = {"error": {"code": code, "message": message, "request_id": request_id}}
    if details:
        payload["error"]["details"] = details
    return jsonify(payload), status


_error = api_error_response


def _json_body():
    if not request.is_json:
        raise ApiError(415, "unsupported_media_type", "Content-Type debe ser application/json.")
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ApiError(400, "invalid_json", "El cuerpo JSON es inválido.")
    return data


def _payload_body():
    """Lee JSON o el campo payload JSON de un multipart con evidencias."""
    if request.is_json:
        return _json_body()
    if request.mimetype and request.mimetype.startswith("multipart/form-data"):
        raw = request.form.get("payload", "")
        try:
            data = json.loads(raw)
        except (TypeError, json.JSONDecodeError) as error:
            raise ApiError(400, "invalid_json", "payload debe contener un objeto JSON válido.") from error
        if not isinstance(data, dict):
            raise ApiError(400, "invalid_json", "payload debe contener un objeto JSON.")
        return data
    raise ApiError(415, "unsupported_media_type", "Content-Type debe ser application/json o multipart/form-data.")


def _token_hash(token):
    # HMAC evita que la tabla de hashes pueda compararse directamente contra
    # tokens generados fuera de la aplicación si la base fuese expuesta.
    return hmac.new(
        current_app.config["API_TOKEN_SECRET"].encode("utf-8"), token.encode("utf-8"), hashlib.sha256
    ).hexdigest()


def _access_token(user):
    now = _utcnow()
    expires = now + timedelta(minutes=current_app.config["API_ACCESS_TOKEN_MINUTES"])
    claims = {
        "iss": current_app.config["API_TOKEN_ISSUER"],
        "sub": str(user.id),
        "role": user.role,
        "iat": now,
        "exp": expires,
        "jti": str(uuid.uuid4()),
        "typ": "access",
    }
    token = jwt.encode(claims, current_app.config["API_TOKEN_SECRET"], algorithm="HS256")
    return token, expires


def _issue_tokens(user, client_name=None):
    access_token, access_expires = _access_token(user)
    raw_refresh = secrets.token_urlsafe(48)
    now = _utcnow()
    refresh_expires = now + timedelta(days=current_app.config["API_REFRESH_TOKEN_DAYS"])
    db.session.add(ApiRefreshToken(
        user_id=user.id,
        token_hash=_token_hash(raw_refresh),
        issued_at=now,
        expires_at=refresh_expires,
        client_name=(client_name or "Flutter")[:100],
    ))
    db.session.commit()
    return {
        "access_token": access_token,
        "token_type": "Bearer",
        "expires_in": int((access_expires - now).total_seconds()),
        "refresh_token": raw_refresh,
        "refresh_expires_in": int((refresh_expires - now).total_seconds()),
        "user": _user_payload(user),
    }


def _user_payload(user):
    return {"id": user.id, "username": user.username, "full_name": user.full_name, "role": user.role}


def _datetime_value(value):
    if not value:
        return None
    return _as_utc(value).isoformat().replace("+00:00", "Z")


def _page_args():
    page = request.args.get("page", 1, type=int)
    page_size = request.args.get("page_size", 25, type=int)
    if not page or page < 1 or not page_size or page_size < 1 or page_size > 100:
        raise ApiError(400, "validation_error", "page debe ser mayor a cero y page_size debe estar entre 1 y 100.")
    return page, page_size


def _optional_int(name):
    raw = request.args.get(name)
    if raw in (None, ""):
        return None
    try:
        value = int(raw)
    except ValueError as error:
        raise ApiError(400, "validation_error", f"{name} debe ser entero.") from error
    if value < 1:
        raise ApiError(400, "validation_error", f"{name} debe ser positivo.")
    return value


def _date_bounds(column, query):
    date_from = request.args.get("date_from")
    date_to = request.args.get("date_to")
    try:
        if date_from:
            start = datetime.fromisoformat(date_from.replace("Z", "+00:00"))
            query = query.where(column >= start)
        if date_to:
            end = datetime.fromisoformat(date_to.replace("Z", "+00:00"))
            # Una fecha sin hora se interpreta de forma inclusiva hasta el día siguiente.
            if "T" not in date_to and " " not in date_to:
                end += timedelta(days=1)
            query = query.where(column < end)
    except ValueError as error:
        raise ApiError(400, "validation_error", "date_from y date_to deben usar ISO-8601.") from error
    return query


def _is_admin():
    # Las bases heredadas pueden contener el mismo rol con distinta
    # capitalización. La autorización sigue basándose exclusivamente en Rol.
    return (g.api_user.role or "").casefold() == "administrador"


def _enforce_technician_scope(query, column, requested_technician_id):
    if _is_admin():
        return query.where(column == requested_technician_id) if requested_technician_id else query
    if requested_technician_id and requested_technician_id != g.api_user.id:
        raise ApiError(403, "insufficient_role", "No puede consultar registros de otro técnico.")
    return query.where(column == g.api_user.id)


def _paginate(query, page, page_size):
    total = db.session.execute(select(func.count()).select_from(query.order_by(None).subquery())).scalar_one()
    items = db.session.execute(query.offset((page - 1) * page_size).limit(page_size)).scalars().all()
    return items, {"page": page, "page_size": page_size, "total": total, "total_pages": (total + page_size - 1) // page_size}


def _report_payload(report, *, detail=False):
    data = {
        "id": report.id,
        "client": report.client,
        "service_type": report.service_type,
        "description": report.description,
        "created_at": _datetime_value(report.created_at),
        "task_started_at": _datetime_value(report.task_started_at),
        "task_finished_at": _datetime_value(report.task_finished_at),
        "technician": _user_payload(report.technician),
        "area": {"id": report.area.id, "name": report.area.name} if report.area else None,
        "section": {"id": report.section.id, "name": report.section.name} if report.section else None,
        "machinery": {"id": report.machinery.id, "name": report.machinery.name} if report.machinery else None,
    }
    if detail:
        checklist = db.session.execute(select(ReportChecklist).where(ReportChecklist.report_id == report.id).order_by(ReportChecklist.id)).scalars().all()
        attachments = db.session.execute(select(Attachment).where(Attachment.report_id == report.id).order_by(Attachment.id)).scalars().all()
        data["checklist"] = [
            {"key": item.question_key, "question": item.question_text, "answer": item.answer, "evidence_attachment_id": item.evidence_attachment_id}
            for item in checklist
        ]
        data["attachments"] = [
            {"id": item.id, "original_name": item.original_name, "mime_type": item.mime_type, "size_bytes": item.file_size,
             "download_path": f"/api/v1/attachments/{item.id}"}
            for item in attachments
        ]
    return data


def _fuel_payload(load, *, detail=False):
    technician = db.session.get(User, load.technician_id)
    data = {
        "id": load.id,
        "loaded_at": _datetime_value(load.loaded_at),
        "created_at": _datetime_value(load.created_at),
        "observations": load.observations,
        "technician": _user_payload(technician),
    }
    if detail:
        details = db.session.execute(
            select(FuelLoadGenerator).where(FuelLoadGenerator.load_id == load.id).order_by(FuelLoadGenerator.generator_number)
        ).scalars().all()
        data["generators"] = [
            {
                "number": item.generator_number, "liters": float(item.liters), "hourmeter": float(item.hourmeter),
                "water_image_recorded": bool(item.water_image), "oil_image_recorded": bool(item.oil_image),
                "water_image_path": f"/api/v1/fuel-loads/{load.id}/generators/{item.generator_number}/images/water",
                "oil_image_path": f"/api/v1/fuel-loads/{load.id}/generators/{item.generator_number}/images/oil",
            }
            for item in details
        ]
    return data


def _api_file_response(storage, key, filename, mime_type):
    if not storage.exists(key):
        raise ApiError(404, "not_found", "El archivo solicitado no existe.")
    response = Response(stream_with_context(storage.iter_bytes(key)), mimetype=mime_type)
    response.headers.set("Content-Disposition", "attachment", filename=filename)
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


def api_login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return _error(401, "missing_access_token", "Se requiere un access token Bearer.")
        token = header[7:].strip()
        if not token:
            return _error(401, "missing_access_token", "Se requiere un access token Bearer.")
        try:
            claims = jwt.decode(
                token,
                current_app.config["API_TOKEN_SECRET"],
                algorithms=["HS256"],
                issuer=current_app.config["API_TOKEN_ISSUER"],
                options={"require": ["exp", "iat", "sub", "jti", "typ"]},
            )
        except jwt.ExpiredSignatureError:
            return _error(401, "access_token_expired", "El access token expiró.")
        except jwt.InvalidTokenError:
            return _error(401, "invalid_access_token", "El access token no es válido.")
        if claims.get("typ") != "access":
            return _error(401, "invalid_access_token", "El tipo de token no es válido.")
        try:
            user_id = int(claims["sub"])
        except (TypeError, ValueError):
            return _error(401, "invalid_access_token", "El access token no es válido.")
        user = db.session.get(User, user_id)
        if not user or not user.is_active:
            return _error(401, "inactive_user", "La cuenta no está disponible.")
        g.api_user = user
        g.api_claims = claims
        return view(*args, **kwargs)
    return wrapped


def api_roles_required(*roles):
    """Decorador reutilizable para endpoints administrativos futuros."""
    def decorator(view):
        @wraps(view)
        @api_login_required
        def wrapped(*args, **kwargs):
            if g.api_user.role not in roles:
                return _error(403, "insufficient_role", "No tiene permiso para esta operación.")
            return view(*args, **kwargs)
        return wrapped
    return decorator


@api_bp.before_request
def api_request_context():
    g.request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))[:100]


@api_bp.errorhandler(ApiError)
def handle_api_error(error):
    return _error(error.status, error.code, error.message, error.details)


@api_bp.errorhandler(404)
def api_not_found(_error_value):
    return _error(404, "not_found", "El recurso solicitado no existe.")


@api_bp.errorhandler(405)
def api_method_not_allowed(_error_value):
    return _error(405, "method_not_allowed", "El método HTTP no está permitido.")


@api_bp.get("/health")
def health():
    return jsonify({"data": {"status": "ok", "version": "v1"}, "request_id": g.request_id})


@api_bp.post("/auth/login")
def login():
    data = _json_body()
    username = str(data.get("username", "")).strip()
    password = data.get("password", "")
    client_name = str(data.get("client_name", "Flutter")).strip()
    if not username or not isinstance(password, str) or not password:
        raise ApiError(400, "validation_error", "username y password son obligatorios.")
    user = db.session.execute(select(User).where(User.username == username)).scalar_one_or_none()
    if not user or not user.is_active or not check_password_hash(user.password_hash, password):
        raise ApiError(401, "invalid_credentials", "Las credenciales no son válidas.")
    return jsonify({"data": _issue_tokens(user, client_name), "request_id": g.request_id}), 200


@api_bp.post("/auth/refresh")
def refresh():
    data = _json_body()
    raw_refresh = data.get("refresh_token", "")
    if not isinstance(raw_refresh, str) or not raw_refresh:
        raise ApiError(400, "validation_error", "refresh_token es obligatorio.")
    now = _utcnow()
    token = db.session.execute(
        select(ApiRefreshToken).where(ApiRefreshToken.token_hash == _token_hash(raw_refresh))
    ).scalar_one_or_none()
    if not token or token.revoked_at or _as_utc(token.expires_at) <= now:
        raise ApiError(401, "invalid_refresh_token", "El refresh token no es válido o expiró.")
    user = db.session.get(User, token.user_id)
    if not user or not user.is_active:
        raise ApiError(401, "inactive_user", "La cuenta no está disponible.")
    # Rotación: un refresh token utilizado deja de servir de inmediato.
    token.revoked_at = now
    token.replaced_at = now
    db.session.flush()
    response = _issue_tokens(user, token.client_name)
    return jsonify({"data": response, "request_id": g.request_id}), 200


@api_bp.post("/auth/logout")
def logout():
    data = _json_body()
    raw_refresh = data.get("refresh_token", "")
    if not isinstance(raw_refresh, str) or not raw_refresh:
        raise ApiError(400, "validation_error", "refresh_token es obligatorio.")
    token = db.session.execute(
        select(ApiRefreshToken).where(ApiRefreshToken.token_hash == _token_hash(raw_refresh))
    ).scalar_one_or_none()
    if token and not token.revoked_at:
        token.revoked_at = _utcnow()
        db.session.commit()
    # Idempotente: no revela si el token existía.
    return jsonify({"data": {"revoked": True}, "request_id": g.request_id}), 200


@api_bp.get("/auth/me")
@api_login_required
def me():
    return jsonify({"data": _user_payload(g.api_user), "request_id": g.request_id}), 200


@api_bp.get("/admin/status")
@api_roles_required("Administrador")
def admin_status():
    """Comprobación mínima que ejercita el control de rol de la API v1."""
    return jsonify({"data": {"status": "ok", "role": g.api_user.role}, "request_id": g.request_id}), 200


@api_bp.get("/areas")
@api_login_required
def areas():
    rows = db.session.execute(select(Area).where(Area.is_active == True).order_by(Area.name)).scalars().all()  # noqa: E712
    return jsonify({"data": [{"id": item.id, "name": item.name} for item in rows], "request_id": g.request_id}), 200


@api_bp.get("/sections")
@api_login_required
def sections():
    area_id = _optional_int("area_id")
    if not area_id:
        raise ApiError(400, "validation_error", "area_id es obligatorio.", {"area_id": "required"})
    area = db.session.get(Area, area_id)
    if not area or not area.is_active:
        raise ApiError(404, "not_found", "El área solicitada no existe o está inactiva.")
    rows = db.session.execute(
        select(Section).where(Section.area_id == area_id, Section.is_active == True).order_by(Section.name)  # noqa: E712
    ).scalars().all()
    return jsonify({"data": [{"id": item.id, "area_id": item.area_id, "name": item.name} for item in rows], "request_id": g.request_id}), 200


@api_bp.get("/machineries")
@api_login_required
def machineries():
    section_id = _optional_int("section_id")
    if not section_id:
        raise ApiError(400, "validation_error", "section_id es obligatorio.", {"section_id": "required"})
    section = db.session.get(Section, section_id)
    if not section or not section.is_active:
        raise ApiError(404, "not_found", "La sección solicitada no existe o está inactiva.")
    rows = db.session.execute(
        select(Machinery).where(Machinery.section_id == section_id, Machinery.is_active == True).order_by(Machinery.name)  # noqa: E712
    ).scalars().all()
    return jsonify({"data": [{"id": item.id, "section_id": item.section_id, "source_code": item.source_code, "name": item.name} for item in rows], "request_id": g.request_id}), 200


@api_bp.get("/reports")
@api_login_required
def reports():
    page, page_size = _page_args()
    technician_id = _optional_int("technician_id")
    query = select(Report).options(
        joinedload(Report.technician), joinedload(Report.area), joinedload(Report.section), joinedload(Report.machinery)
    )
    query = _enforce_technician_scope(query, Report.technician_id, technician_id)
    for name, column in (("area_id", Report.area_id), ("section_id", Report.section_id), ("machinery_id", Report.machinery_id)):
        value = _optional_int(name)
        if value:
            query = query.where(column == value)
    service_type = request.args.get("service_type", "").strip()
    if service_type:
        if service_type not in SERVICE_TYPES:
            raise ApiError(400, "validation_error", "service_type no es válido.")
        query = query.where(Report.service_type == service_type)
    query = _date_bounds(Report.created_at, query).order_by(Report.created_at.desc(), Report.id.desc())
    rows, pagination = _paginate(query, page, page_size)
    return jsonify({"data": [_report_payload(item) for item in rows], "pagination": pagination, "request_id": g.request_id}), 200


def _dashboard_filters():
    """Lee filtros comunes y valida la jerarquía de catálogos una sola vez."""
    record_type = request.args.get("record_type", "all").strip().lower()
    if record_type not in {"all", "maintenance", "fuel"}:
        raise ApiError(400, "validation_error", "record_type debe ser all, maintenance o fuel.")
    filters = {
        "record_type": record_type,
        "technician_id": _optional_int("technician_id"),
        "area_id": _optional_int("area_id"),
        "section_id": _optional_int("section_id"),
        "machinery_id": _optional_int("machinery_id"),
        "service_type": request.args.get("service_type", "").strip() or None,
        "date_from": request.args.get("date_from") or None,
        "date_to": request.args.get("date_to") or None,
    }
    if filters["service_type"] and filters["service_type"] not in SERVICE_TYPES:
        raise ApiError(400, "validation_error", "service_type no es válido.")
    section_id, area_id, machinery_id = filters["section_id"], filters["area_id"], filters["machinery_id"]
    section = db.session.get(Section, section_id) if section_id else None
    machine = db.session.get(Machinery, machinery_id) if machinery_id else None
    if section and area_id and section.area_id != area_id:
        raise ApiError(400, "validation_error", "section_id no pertenece a area_id.")
    if machine and section_id and machine.section_id != section_id:
        raise ApiError(400, "validation_error", "machinery_id no pertenece a section_id.")
    if machine and area_id:
        machine_section = db.session.get(Section, machine.section_id)
        if not machine_section or machine_section.area_id != area_id:
            raise ApiError(400, "validation_error", "machinery_id no pertenece a area_id.")
    return filters


def _dashboard_report_query(filters):
    query = _enforce_technician_scope(select(Report), Report.technician_id, filters["technician_id"])
    for key, column in (("area_id", Report.area_id), ("section_id", Report.section_id), ("machinery_id", Report.machinery_id)):
        if filters[key]:
            query = query.where(column == filters[key])
    if filters["service_type"]:
        query = query.where(Report.service_type == filters["service_type"])
    return _date_bounds(Report.created_at, query)


def _dashboard_fuel_query(filters):
    # Área, sección, maquinaria y servicio no existen en CargasPetroleoGeneradores.
    return _date_bounds(
        FuelLoad.loaded_at,
        _enforce_technician_scope(select(FuelLoad), FuelLoad.technician_id, filters["technician_id"]),
    )


def _dashboard_page_args():
    page = request.args.get("activity_page", 1, type=int)
    page_size = request.args.get("activity_page_size", 20, type=int)
    if not page or page < 1 or not page_size or page_size < 1 or page_size > 100:
        raise ApiError(400, "validation_error", "activity_page debe ser mayor a cero y activity_page_size debe estar entre 1 y 100.")
    return page, page_size


def _grouped_days(query, column):
    # SQL Server soporta CAST(... AS DATE); SQLite (usado por las pruebas)
    # representa fechas tipadas como texto y necesita date(...).
    day = (
        func.date(column)
        if db.engine.dialect.name == "sqlite"
        else cast(column, Date)
    ).label("day")
    rows = db.session.execute(query.with_only_columns(day, func.count()).group_by(day).order_by(day)).all()
    return {str(item.day): int(item[1]) for item in rows}


def _distribution(query, join_model, report_column, label="name", limit=8):
    rows = db.session.execute(
        query.with_only_columns(join_model.id, getattr(join_model, label), func.count(Report.id))
        .outerjoin(join_model, report_column == join_model.id)
        .group_by(join_model.id, getattr(join_model, label))
        .order_by(func.count(Report.id).desc(), getattr(join_model, label))
        .limit(limit)
    ).all()
    return [{"id": item[0], "name": item[1] or "Sin registro", "count": int(item[2])} for item in rows]


@api_bp.get("/dashboard/summary")
@api_login_required
def dashboard_summary():
    """Agregaciones SQL autorizadas para el dashboard móvil."""
    filters = _dashboard_filters()
    activity_page, activity_page_size = _dashboard_page_args()
    report_query = _dashboard_report_query(filters)
    fuel_query = _dashboard_fuel_query(filters)
    include_reports = filters["record_type"] in {"all", "maintenance"}
    include_fuel = filters["record_type"] in {"all", "fuel"}
    report_count = int(db.session.scalar(select(func.count()).select_from(report_query.subquery())) or 0) if include_reports else 0
    fuel_count = int(db.session.scalar(select(func.count()).select_from(fuel_query.subquery())) or 0) if include_fuel else 0

    daily = {}
    if include_reports:
        for day, count in _grouped_days(report_query, Report.created_at).items():
            daily[day] = daily.get(day, 0) + count
    if include_fuel:
        for day, count in _grouped_days(fuel_query, FuelLoad.loaded_at).items():
            daily[day] = daily.get(day, 0) + count

    charts = {"records_by_day": [{"date": day, "count": count} for day, count in sorted(daily.items())]}
    if include_reports:
        charts.update({
            "areas": _distribution(report_query, Area, Report.area_id),
            "sections": _distribution(report_query, Section, Report.section_id),
            "machineries": _distribution(report_query, Machinery, Report.machinery_id),
            "service_types": [
                {"name": row[0], "count": int(row[1])}
                for row in db.session.execute(
                    report_query.with_only_columns(Report.service_type, func.count(Report.id))
                    .group_by(Report.service_type).order_by(func.count(Report.id).desc(), Report.service_type)
                ).all()
            ],
        })
    else:
        charts.update({"areas": [], "sections": [], "machineries": [], "service_types": []})

    activity_parts = []
    if include_reports:
        activity_parts.append(
            report_query.with_only_columns(
                literal("maintenance").label("record_type"), Report.id.label("id"), Report.created_at.label("occurred_at"),
                User.full_name.label("technician_name"), Area.name.label("area_name"), Section.name.label("section_name"),
                Machinery.name.label("machinery_name"), Report.service_type.label("service_type"), Report.client.label("title"), Report.description.label("summary"),
            ).join(User, Report.technician_id == User.id).outerjoin(Area, Report.area_id == Area.id)
            .outerjoin(Section, Report.section_id == Section.id).outerjoin(Machinery, Report.machinery_id == Machinery.id)
        )
    if include_fuel:
        activity_parts.append(
            fuel_query.with_only_columns(
                literal("fuel").label("record_type"), FuelLoad.id.label("id"), FuelLoad.loaded_at.label("occurred_at"),
                User.full_name.label("technician_name"), cast(literal(None), String).label("area_name"),
                cast(literal(None), String).label("section_name"), cast(literal(None), String).label("machinery_name"),
                literal("Carga de petróleo").label("service_type"), literal("Carga de petróleo").label("title"), FuelLoad.observations.label("summary"),
            ).join(User, FuelLoad.technician_id == User.id)
        )
    activity_union = union_all(*activity_parts).subquery()
    activity_total = int(db.session.scalar(select(func.count()).select_from(activity_union)) or 0)
    activity_rows = db.session.execute(
        select(activity_union).order_by(activity_union.c.occurred_at.desc(), activity_union.c.id.desc())
        .offset((activity_page - 1) * activity_page_size).limit(activity_page_size)
    ).mappings().all()
    activity = [
        {**dict(item), "occurred_at": _datetime_value(item["occurred_at"])}
        for item in activity_rows
    ]
    if _is_admin():
        technicians = db.session.execute(select(User).where(User.is_active == True).order_by(User.full_name)).scalars().all()  # noqa: E712
    else:
        technicians = [g.api_user]
    return jsonify({
        "data": {
            "summary": {"total_records": report_count + fuel_count, "maintenance_reports": report_count, "fuel_loads": fuel_count, "activity_days": len(daily)},
            "charts": charts,
            "activity": activity,
            "activity_pagination": {"page": activity_page, "page_size": activity_page_size, "total": activity_total, "total_pages": (activity_total + activity_page_size - 1) // activity_page_size},
            "technicians": [_user_payload(user) for user in technicians],
            "applied_filters": filters,
        },
        "request_id": g.request_id,
    }), 200


@api_bp.get("/reports/<int:report_id>")
@api_login_required
def report_detail(report_id):
    query = select(Report).options(
        joinedload(Report.technician), joinedload(Report.area), joinedload(Report.section), joinedload(Report.machinery)
    ).where(Report.id == report_id)
    query = _enforce_technician_scope(query, Report.technician_id, None)
    report = db.session.execute(query).scalar_one_or_none()
    if not report:
        raise ApiError(404, "not_found", "El reporte solicitado no existe.")
    return jsonify({"data": _report_payload(report, detail=True), "request_id": g.request_id}), 200


@api_bp.get("/attachments/<int:attachment_id>")
@api_login_required
def download_attachment(attachment_id):
    attachment = db.session.get(Attachment, attachment_id)
    if not attachment:
        raise ApiError(404, "not_found", "El adjunto solicitado no existe.")
    report = db.session.get(Report, attachment.report_id)
    if not report or (not _is_admin() and report.technician_id != g.api_user.id):
        # No revela la existencia del adjunto a otro técnico.
        raise ApiError(404, "not_found", "El adjunto solicitado no existe.")
    try:
        storage = get_file_storage()
        return _api_file_response(storage, resolve_report_key(storage, report.id, attachment.stored_name), attachment.original_name, attachment.mime_type)
    except StorageError as error:
        current_app.logger.exception("Error al recuperar adjunto API %s", attachment.id)
        raise ApiError(503, "storage_unavailable", "No fue posible recuperar el archivo.") from error


@api_bp.post("/reports")
@api_login_required
def create_report():
    data = _payload_body()
    evidence = {key: request.files.get(f"evidence_{key}") for key, _, expected in CHECKLIST if expected}
    try:
        report = create_maintenance_report(
            data=data, technician_id=g.api_user.id, evidence_files=evidence,
            attachments=request.files.getlist("attachments"), upload_folder=current_app.config["UPLOAD_FOLDER"],
        )
    except BusinessRuleError as error:
        raise ApiError(422, error.code, str(error), error.details) from error
    report = db.session.execute(
        select(Report).options(joinedload(Report.technician), joinedload(Report.area), joinedload(Report.section), joinedload(Report.machinery)).where(Report.id == report.id)
    ).scalar_one()
    return jsonify({"data": _report_payload(report, detail=True), "request_id": g.request_id}), 201


@api_bp.get("/fuel-loads")
@api_login_required
def fuel_loads():
    page, page_size = _page_args()
    technician_id = _optional_int("technician_id")
    query = _enforce_technician_scope(select(FuelLoad), FuelLoad.technician_id, technician_id)
    query = _date_bounds(FuelLoad.loaded_at, query).order_by(FuelLoad.loaded_at.desc(), FuelLoad.id.desc())
    rows, pagination = _paginate(query, page, page_size)
    return jsonify({"data": [_fuel_payload(item, detail=True) for item in rows], "pagination": pagination, "request_id": g.request_id}), 200


@api_bp.get("/fuel-loads/<int:load_id>")
@api_login_required
def fuel_load_detail(load_id):
    query = _enforce_technician_scope(select(FuelLoad).where(FuelLoad.id == load_id), FuelLoad.technician_id, None)
    load = db.session.execute(query).scalar_one_or_none()
    if not load:
        raise ApiError(404, "not_found", "La carga de petróleo solicitada no existe.")
    return jsonify({"data": _fuel_payload(load, detail=True), "request_id": g.request_id}), 200


@api_bp.get("/fuel-loads/<int:load_id>/generators/<int:generator_number>/images/<kind>")
@api_login_required
def download_fuel_image(load_id, generator_number, kind):
    if kind not in {"water", "oil"}:
        raise ApiError(404, "not_found", "La fotografía solicitada no existe.")
    query = _enforce_technician_scope(select(FuelLoad).where(FuelLoad.id == load_id), FuelLoad.technician_id, None)
    load = db.session.execute(query).scalar_one_or_none()
    if not load:
        raise ApiError(404, "not_found", "La carga de petróleo solicitada no existe.")
    detail = db.session.execute(select(FuelLoadGenerator).where(
        FuelLoadGenerator.load_id == load_id, FuelLoadGenerator.generator_number == generator_number
    )).scalar_one_or_none()
    if not detail:
        raise ApiError(404, "not_found", "La fotografía solicitada no existe.")
    try:
        storage = get_file_storage()
        stored_name = detail.water_image if kind == "water" else detail.oil_image
        return _api_file_response(storage, resolve_fuel_key(storage, load_id, stored_name), f"generador_{generator_number}_{kind}.png", "image/png")
    except StorageError as error:
        current_app.logger.exception("Error al recuperar fotografía API de carga %s", load_id)
        raise ApiError(503, "storage_unavailable", "No fue posible recuperar el archivo.") from error


@api_bp.post("/fuel-loads")
@api_login_required
def create_fuel_load_endpoint():
    data = _payload_body()
    images = {(number, kind): request.files.get(f"{kind}_{number}") for number in (1, 2) for kind in ("water", "oil")}
    try:
        load = create_fuel_load(
            data=data, technician_id=g.api_user.id, images=images, upload_folder=current_app.config["UPLOAD_FOLDER"],
        )
    except BusinessRuleError as error:
        raise ApiError(422, error.code, str(error), error.details) from error
    return jsonify({"data": _fuel_payload(load, detail=True), "request_id": g.request_id}), 201
