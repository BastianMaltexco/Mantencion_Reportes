"""Consultas autorizadas y compartidas para el Dashboard.

Este módulo es la única fuente de verdad para los filtros, el alcance por rol y
las agregaciones. La API móvil, el Dashboard web y sus exportaciones lo usan
para evitar que un archivo descargado difiera de lo que muestra el Dashboard.
"""
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta
from typing import Mapping

from sqlalchemy import Date, String, cast, func, literal, select, union_all
from sqlalchemy.orm import joinedload

from app import db
from app.models import Area, FuelLoad, FuelLoadGenerator, Machinery, Report, Section, User
from app.services.field_reports import SERVICE_TYPES


class DashboardValidationError(ValueError):
    """Filtro inválido que debe convertirse a un error de entrada HTTP."""


class DashboardPermissionError(PermissionError):
    """Un técnico intentó consultar registros ajenos."""


@dataclass(frozen=True)
class DashboardFilters:
    record_type: str = "all"
    technician_id: int | None = None
    area_id: int | None = None
    section_id: int | None = None
    machinery_id: int | None = None
    service_type: str | None = None
    date_from: str | None = None
    date_to: str | None = None

    def payload(self):
        return asdict(self)


def _positive_int(args: Mapping[str, str], name: str):
    raw = args.get(name)
    if raw in (None, ""):
        return None
    try:
        value = int(raw)
    except (TypeError, ValueError) as error:
        raise DashboardValidationError(f"{name} debe ser entero.") from error
    if value < 1:
        raise DashboardValidationError(f"{name} debe ser positivo.")
    return value


def parse_filters(args: Mapping[str, str]) -> DashboardFilters:
    """Convierte parámetros HTTP en filtros y valida catálogos relacionados."""
    record_type = (args.get("record_type") or "all").strip().lower()
    if record_type not in {"all", "maintenance", "fuel"}:
        raise DashboardValidationError("record_type debe ser all, maintenance o fuel.")
    service_type = (args.get("service_type") or "").strip() or None
    if service_type and service_type not in SERVICE_TYPES:
        raise DashboardValidationError("service_type no es válido.")
    filters = DashboardFilters(
        record_type=record_type,
        technician_id=_positive_int(args, "technician_id"),
        area_id=_positive_int(args, "area_id"),
        section_id=_positive_int(args, "section_id"),
        machinery_id=_positive_int(args, "machinery_id"),
        service_type=service_type,
        date_from=args.get("date_from") or None,
        date_to=args.get("date_to") or None,
    )
    section = db.session.get(Section, filters.section_id) if filters.section_id else None
    machinery = db.session.get(Machinery, filters.machinery_id) if filters.machinery_id else None
    if section and filters.area_id and section.area_id != filters.area_id:
        raise DashboardValidationError("section_id no pertenece a area_id.")
    if machinery and filters.section_id and machinery.section_id != filters.section_id:
        raise DashboardValidationError("machinery_id no pertenece a section_id.")
    if machinery and filters.area_id:
        machinery_section = db.session.get(Section, machinery.section_id)
        if not machinery_section or machinery_section.area_id != filters.area_id:
            raise DashboardValidationError("machinery_id no pertenece a area_id.")
    # Valida los formatos incluso si no hay registros para que API y web se
    # comporten igual ante una fecha inválida.
    _parse_date_bound(filters.date_from)
    _parse_date_bound(filters.date_to)
    return filters


def _parse_date_bound(value: str | None):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise DashboardValidationError("date_from y date_to deben usar ISO-8601.") from error


def _date_bounds(column, query, filters: DashboardFilters):
    start = _parse_date_bound(filters.date_from)
    end = _parse_date_bound(filters.date_to)
    if start:
        query = query.where(column >= start)
    if end:
        # Un valor solamente de fecha incluye todo ese día.
        if "T" not in filters.date_to and " " not in filters.date_to:
            end += timedelta(days=1)
        query = query.where(column < end)
    return query


def _authorized_query(query, column, filters: DashboardFilters, *, actor_id: int, is_admin: bool):
    if is_admin:
        return query.where(column == filters.technician_id) if filters.technician_id else query
    if filters.technician_id and filters.technician_id != actor_id:
        raise DashboardPermissionError("No puede consultar registros de otro técnico.")
    return query.where(column == actor_id)


def report_query(filters: DashboardFilters, *, actor_id: int, is_admin: bool):
    query = _authorized_query(select(Report), Report.technician_id, filters, actor_id=actor_id, is_admin=is_admin)
    for key, column in (("area_id", Report.area_id), ("section_id", Report.section_id), ("machinery_id", Report.machinery_id)):
        if getattr(filters, key):
            query = query.where(column == getattr(filters, key))
    if filters.service_type:
        query = query.where(Report.service_type == filters.service_type)
    return _date_bounds(Report.created_at, query, filters)


def fuel_query(filters: DashboardFilters, *, actor_id: int, is_admin: bool):
    # Área, sección, maquinaria y servicio no existen en una carga de petróleo.
    query = _authorized_query(select(FuelLoad), FuelLoad.technician_id, filters, actor_id=actor_id, is_admin=is_admin)
    return _date_bounds(FuelLoad.loaded_at, query, filters)


def _grouped_days(query, column):
    day = (func.date(column) if db.engine.dialect.name == "sqlite" else cast(column, Date)).label("day")
    rows = db.session.execute(query.with_only_columns(day, func.count()).group_by(day).order_by(day)).all()
    return {str(item.day): int(item[1]) for item in rows}


def _distribution(query, join_model, report_column, label="name", limit=8):
    rows = db.session.execute(
        query.with_only_columns(join_model.id, getattr(join_model, label), func.count(Report.id))
        .outerjoin(join_model, report_column == join_model.id)
        .group_by(join_model.id, getattr(join_model, label))
        .order_by(func.count(Report.id).desc(), getattr(join_model, label)).limit(limit)
    ).all()
    return [{"id": row[0], "name": row[1] or "Sin registro", "count": int(row[2])} for row in rows]


def dashboard_summary(filters: DashboardFilters, *, actor_id: int, is_admin: bool, activity_page=1, activity_page_size=20):
    """Devuelve las agregaciones SQL y actividad filtrada sin depender de Flask."""
    if activity_page < 1 or activity_page_size < 1 or activity_page_size > 100:
        raise DashboardValidationError("activity_page debe ser mayor a cero y activity_page_size debe estar entre 1 y 100.")
    reports = report_query(filters, actor_id=actor_id, is_admin=is_admin)
    fuel_loads = fuel_query(filters, actor_id=actor_id, is_admin=is_admin)
    include_reports = filters.record_type in {"all", "maintenance"}
    include_fuel = filters.record_type in {"all", "fuel"}
    report_count = int(db.session.scalar(select(func.count()).select_from(reports.subquery())) or 0) if include_reports else 0
    fuel_count = int(db.session.scalar(select(func.count()).select_from(fuel_loads.subquery())) or 0) if include_fuel else 0

    daily = {}
    if include_reports:
        for day, count in _grouped_days(reports, Report.created_at).items():
            daily[day] = daily.get(day, 0) + count
    if include_fuel:
        for day, count in _grouped_days(fuel_loads, FuelLoad.loaded_at).items():
            daily[day] = daily.get(day, 0) + count
    charts = {"records_by_day": [{"date": day, "count": count} for day, count in sorted(daily.items())]}
    if include_reports:
        charts.update({
            "areas": _distribution(reports, Area, Report.area_id),
            "sections": _distribution(reports, Section, Report.section_id),
            "machineries": _distribution(reports, Machinery, Report.machinery_id),
            "service_types": [{"name": row[0], "count": int(row[1])} for row in db.session.execute(
                reports.with_only_columns(Report.service_type, func.count(Report.id)).group_by(Report.service_type)
                .order_by(func.count(Report.id).desc(), Report.service_type)
            ).all()],
        })
    else:
        charts.update({"areas": [], "sections": [], "machineries": [], "service_types": []})

    activity_parts = []
    if include_reports:
        activity_parts.append(reports.with_only_columns(
            literal("maintenance").label("record_type"), Report.id.label("id"), Report.created_at.label("occurred_at"),
            User.full_name.label("technician_name"), Area.name.label("area_name"), Section.name.label("section_name"),
            Machinery.name.label("machinery_name"), Report.service_type.label("service_type"), Report.client.label("title"), Report.description.label("summary"),
        ).join(User, Report.technician_id == User.id).outerjoin(Area, Report.area_id == Area.id)
         .outerjoin(Section, Report.section_id == Section.id).outerjoin(Machinery, Report.machinery_id == Machinery.id))
    if include_fuel:
        activity_parts.append(fuel_loads.with_only_columns(
            literal("fuel").label("record_type"), FuelLoad.id.label("id"), FuelLoad.loaded_at.label("occurred_at"),
            User.full_name.label("technician_name"), cast(literal(None), String).label("area_name"),
            cast(literal(None), String).label("section_name"), cast(literal(None), String).label("machinery_name"),
            literal("Carga de petróleo").label("service_type"), literal("Carga de petróleo").label("title"), FuelLoad.observations.label("summary"),
        ).join(User, FuelLoad.technician_id == User.id))
    activity_union = union_all(*activity_parts).subquery()
    activity_total = int(db.session.scalar(select(func.count()).select_from(activity_union)) or 0)
    activity_rows = db.session.execute(select(activity_union).order_by(activity_union.c.occurred_at.desc(), activity_union.c.id.desc())
        .offset((activity_page - 1) * activity_page_size).limit(activity_page_size)).mappings().all()
    return {
        "summary": {"total_records": report_count + fuel_count, "maintenance_reports": report_count, "fuel_loads": fuel_count, "activity_days": len(daily)},
        "charts": charts,
        "activity": [dict(row) for row in activity_rows],
        "activity_pagination": {"page": activity_page, "page_size": activity_page_size, "total": activity_total, "total_pages": (activity_total + activity_page_size - 1) // activity_page_size},
        "applied_filters": filters.payload(),
    }


def dashboard_export_records(filters: DashboardFilters, *, actor_id: int, is_admin: bool):
    """Filas de detalle para exportar, usando exactamente las consultas filtradas."""
    reports, fuel_loads = [], []
    if filters.record_type in {"all", "maintenance"}:
        reports = db.session.execute(report_query(filters, actor_id=actor_id, is_admin=is_admin).options(
            joinedload(Report.technician), joinedload(Report.area), joinedload(Report.section), joinedload(Report.machinery)
        ).order_by(Report.created_at.desc(), Report.id.desc())).scalars().all()
    if filters.record_type in {"all", "fuel"}:
        fuel_loads = db.session.execute(
            fuel_query(filters, actor_id=actor_id, is_admin=is_admin).order_by(FuelLoad.loaded_at.desc(), FuelLoad.id.desc())
        ).scalars().all()
        # FuelLoad no define relación histórica con User/detalles; se consulta
        # explícitamente para mantener compatibilidad con el esquema existente.
        details = db.session.execute(select(FuelLoadGenerator).where(FuelLoadGenerator.load_id.in_([item.id for item in fuel_loads]))).scalars().all() if fuel_loads else []
        users = {user.id: user for user in db.session.execute(select(User).where(User.id.in_([item.technician_id for item in fuel_loads]))).scalars().all()} if fuel_loads else {}
        detail_map = {(item.load_id, item.generator_number): item for item in details}
        return reports, [(item, users.get(item.technician_id), detail_map) for item in fuel_loads]
    return reports, fuel_loads
