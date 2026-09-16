from flask import Blueprint, Response, current_app, flash, jsonify, redirect, render_template, request, send_file, session, stream_with_context, url_for
from sqlalchemy import func, select

from app import db, login_required
from app.models import Area, Attachment, FuelLoad, FuelLoadGenerator, Machinery, Report, ReportChecklist, Section, User
from app.services.field_reports import (
    BusinessRuleError, CHECKLIST, IMAGE_EXTENSIONS, SERVICE_TYPES,
    create_fuel_load as create_fuel_load_service,
    create_maintenance_report,
)
from app.services.storage import StorageError, get_file_storage, resolve_fuel_key, resolve_report_key
from app.services.dashboard import (
    DashboardPermissionError, DashboardValidationError, dashboard_export_records,
    dashboard_summary as build_dashboard_summary, parse_filters,
)
from app.services.dashboard_export import csv_bytes, xlsx_bytes

reports_bp = Blueprint("reports", __name__)


def _can_access_record(technician_id):
    return (session.get("role") or "").casefold() == "administrador" or technician_id == session.get("user_id")


def _file_response(storage, key, filename, mime_type, *, attachment=True):
    if not storage.exists(key):
        return "Archivo no encontrado.", 404
    response = Response(stream_with_context(storage.iter_bytes(key)), mimetype=mime_type)
    response.headers.set("Content-Disposition", "attachment" if attachment else "inline", filename=filename)
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response
@reports_bp.get("/")
@login_required
def dashboard():
    query = _filtered_reports().order_by(Report.created_at.desc())
    reports = db.session.execute(query).scalars().all()
    # SQL Server usa "= 1" para BIT; "IS 1" no es sintaxis válida.
    technicians = db.session.execute(select(User).where(User.is_active == True).order_by(User.full_name)).scalars().all()  # noqa: E712
    return render_template("dashboard.html", reports=reports, technicians=technicians, areas=db.session.execute(select(Area).order_by(Area.name)).scalars().all(), sections=db.session.execute(select(Section).order_by(Section.name)).scalars().all(), machines=db.session.execute(select(Machinery).order_by(Machinery.name)).scalars().all())


def _filtered_reports():
    query = select(Report)
    client = request.args.get("client", "").strip()
    for column, value in ((Report.technician_id, request.args.get("technician_id", type=int)), (Report.area_id, request.args.get("area_id", type=int)), (Report.section_id, request.args.get("section_id", type=int)), (Report.machinery_id, request.args.get("machinery_id", type=int))):
        if value: query = query.where(column == value)
    if client: query = query.where(Report.client.ilike(f"%{client}%"))
    if request.args.get("date_from"): query = query.where(Report.created_at >= request.args["date_from"])
    if request.args.get("date_to"): query = query.where(Report.created_at < f"{request.args['date_to']} 23:59:59.9999999")
    return query


@reports_bp.get("/dashboard")
@login_required
def metrics_dashboard():
    is_admin = (session.get("role") or "").casefold() == "administrador"
    activity_page = request.args.get("activity_page", 1, type=int) or 1
    try:
        filters = parse_filters(request.args)
        data = build_dashboard_summary(filters, actor_id=session["user_id"], is_admin=is_admin, activity_page=activity_page, activity_page_size=50)
    except DashboardValidationError as error:
        flash(str(error), "error")
        return redirect(url_for("reports.metrics_dashboard"))
    except DashboardPermissionError:
        return "Acceso no autorizado.", 403
    technicians = (db.session.execute(select(User).where(User.is_active == True).order_by(User.full_name)).scalars().all()  # noqa: E712
                   if is_admin else [db.session.get(User, session["user_id"])])
    active_args = request.args.to_dict(flat=True)
    page_args = {key: value for key, value in active_args.items() if key != "activity_page"}
    pagination = data["activity_pagination"]
    return render_template(
        "metrics_dashboard.html", dashboard=data, filters=filters, technicians=technicians,
        areas=db.session.execute(select(Area).where(Area.is_active == True).order_by(Area.name)).scalars().all(),  # noqa: E712
        sections=db.session.execute(select(Section).where(Section.is_active == True).order_by(Section.name)).scalars().all(),  # noqa: E712
        machines=db.session.execute(select(Machinery).where(Machinery.is_active == True).order_by(Machinery.name)).scalars().all(),  # noqa: E712
        service_types=SERVICE_TYPES, is_admin=is_admin,
        export_xlsx_url=url_for("reports.dashboard_export", **{**active_args, "format": "xlsx"}),
        export_csv_url=url_for("reports.dashboard_export", **{**active_args, "format": "csv"}),
        activity_previous_url=(url_for("reports.metrics_dashboard", **{**page_args, "activity_page": pagination["page"] - 1}) if pagination["page"] > 1 else None),
        activity_next_url=(url_for("reports.metrics_dashboard", **{**page_args, "activity_page": pagination["page"] + 1}) if pagination["page"] < pagination["total_pages"] else None),
    )


def _dashboard_filter_labels(filters, is_admin):
    """Etiquetas legibles para la hoja Resumen, sin cambiar los filtros efectivos."""
    user = db.session.get(User, filters.technician_id) if filters.technician_id else None
    area = db.session.get(Area, filters.area_id) if filters.area_id else None
    section = db.session.get(Section, filters.section_id) if filters.section_id else None
    machine = db.session.get(Machinery, filters.machinery_id) if filters.machinery_id else None
    return [
        ("Período desde", filters.date_from), ("Período hasta", filters.date_to),
        ("Técnico / trabajador", user.full_name if user else ("Todos" if is_admin else session.get("user_name"))),
        ("Tipo de registro", {"all": "Todos", "maintenance": "Mantención", "fuel": "Carga de petróleo"}[filters.record_type]),
        ("Área", area.name if area else None), ("Sección", section.name if section else None),
        ("Maquinaria", machine.name if machine else None), ("Tipo de servicio", filters.service_type),
    ]


@reports_bp.get("/dashboard/export")
@login_required
def dashboard_export():
    """Descarga en memoria; jamás publica el archivo ni credenciales de Blob."""
    export_format = (request.args.get("format") or "").lower()
    if export_format not in {"xlsx", "csv"}:
        return "Formato de exportación no válido.", 400
    is_admin = (session.get("role") or "").casefold() == "administrador"
    try:
        filters = parse_filters(request.args)
        data = build_dashboard_summary(filters, actor_id=session["user_id"], is_admin=is_admin, activity_page=1, activity_page_size=1)
        reports, fuel_loads = dashboard_export_records(filters, actor_id=session["user_id"], is_admin=is_admin)
    except DashboardValidationError as error:
        return str(error), 400
    except DashboardPermissionError:
        return "Acceso no autorizado.", 403
    if export_format == "xlsx":
        payload = xlsx_bytes(data, reports, fuel_loads, _dashboard_filter_labels(filters, is_admin))
        return send_file(payload, as_attachment=True, download_name="dashboard_reportes.xlsx", mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    return Response(csv_bytes(reports, fuel_loads), mimetype="text/csv; charset=utf-8", headers={"Content-Disposition": "attachment; filename=dashboard_reportes.csv"})


@reports_bp.get("/reports/new")
@login_required
def choose_report():
    return render_template("choose_report.html")

@reports_bp.route("/reports/maintenance/new", methods=["GET", "POST"])
@login_required
def create_report():
    if request.method == "POST":
        data = {
            "client": request.form.get("client", ""),
            "service_type": request.form.get("service_type", ""),
            "description": request.form.get("description", ""),
            "area_id": request.form.get("area_id"),
            "section_id": request.form.get("section_id"),
            "machinery_id": request.form.get("machinery_id"),
            "task_started_at": request.form.get("task_started_at", ""),
            "task_finished_at": request.form.get("task_finished_at", ""),
            "checklist": {key: request.form.get(f"check_{key}", "") for key, _, _ in CHECKLIST},
        }
        evidence_files = {key: request.files.get(f"evidence_{key}") for key, _, expected in CHECKLIST if expected}
        try:
            report = create_maintenance_report(
                data=data, technician_id=session["user_id"], evidence_files=evidence_files,
                attachments=request.files.getlist("attachments"), upload_folder=current_app.config["UPLOAD_FOLDER"],
            )
            flash("Reporte registrado y sellado con la hora del servidor.", "success")
            return redirect(url_for("reports.report_detail", report_id=report.id))
        except BusinessRuleError as error:
            flash(str(error), "error")
    return render_template("create_report.html", service_types=SERVICE_TYPES, checklist=CHECKLIST)

@reports_bp.route("/reports/fuel/new", methods=["GET", "POST"])
@login_required
def create_fuel_load():
    if request.method == "POST":
        data = {
            "loaded_at": request.form.get("loaded_at", ""), "observations": request.form.get("observations", ""),
            "generators": [{"number": number, "liters": request.form.get(f"liters_{number}"), "hourmeter": request.form.get(f"hourmeter_{number}")} for number in (1, 2)],
        }
        images = {(number, kind): request.files.get(f"{kind}_{number}") for number in (1, 2) for kind in ("water", "oil")}
        try:
            create_fuel_load_service(data=data, technician_id=session["user_id"], images=images, upload_folder=current_app.config["UPLOAD_FOLDER"])
            flash("Carga de petróleo registrada.", "success")
            return redirect(url_for("reports.dashboard"))
        except BusinessRuleError as error:
            flash(str(error), "error")
    return render_template("fuel_load.html")


@reports_bp.get("/api/areas")
@login_required
def areas_api():
    areas = db.session.execute(select(Area).where(Area.is_active == True).order_by(Area.name)).scalars().all()  # noqa: E712
    return jsonify([{"id": area.id, "name": area.name} for area in areas])


@reports_bp.get("/api/sections")
@login_required
def sections_api():
    area_id = request.args.get("area_id", type=int)
    if not area_id:
        return jsonify([])
    sections = db.session.execute(select(Section).where(Section.area_id == area_id, Section.is_active == True).order_by(Section.name)).scalars().all()  # noqa: E712
    return jsonify([{"id": section.id, "name": section.name} for section in sections])


@reports_bp.get("/api/machineries")
@login_required
def machineries_api():
    section_id = request.args.get("section_id", type=int)
    if not section_id:
        return jsonify([])
    machines = db.session.execute(select(Machinery).where(Machinery.section_id == section_id, Machinery.is_active == True).order_by(Machinery.name)).scalars().all()  # noqa: E712
    return jsonify([{"id": machine.id, "name": machine.name} for machine in machines])


@reports_bp.get("/reports/<int:report_id>")
@login_required
def report_detail(report_id):
    report = db.get_or_404(Report, report_id)
    checklist = db.session.execute(select(ReportChecklist).where(ReportChecklist.report_id == report.id).order_by(ReportChecklist.id)).scalars().all()
    return render_template("report_detail.html", report=report, checklist=checklist, image_extensions=IMAGE_EXTENSIONS)


@reports_bp.get("/reports/<int:report_id>/print")
@login_required
def print_report(report_id):
    report = db.get_or_404(Report, report_id)
    return render_template("report_print.html", report=report)


@reports_bp.get("/attachments/<int:attachment_id>")
@login_required
def download_attachment(attachment_id):
    attachment = db.get_or_404(Attachment, attachment_id)
    report = db.get_or_404(Report, attachment.report_id)
    if not _can_access_record(report.technician_id):
        return "Acceso no autorizado.", 403
    try:
        storage = get_file_storage()
        key = resolve_report_key(storage, attachment.report_id, attachment.stored_name)
        return _file_response(storage, key, attachment.original_name, attachment.mime_type, attachment=request.args.get("view") != "1")
    except StorageError:
        current_app.logger.exception("Error al recuperar adjunto %s", attachment.id)
        return "No fue posible recuperar el archivo.", 503


@reports_bp.get("/fuel-loads/<int:load_id>/generators/<int:generator_number>/images/<kind>")
@login_required
def view_fuel_image(load_id, generator_number, kind):
    if kind not in {"water", "oil"}:
        return "Archivo no encontrado.", 404
    load = db.get_or_404(FuelLoad, load_id)
    if not _can_access_record(load.technician_id):
        return "Acceso no autorizado.", 403
    detail = db.session.execute(select(FuelLoadGenerator).where(
        FuelLoadGenerator.load_id == load_id, FuelLoadGenerator.generator_number == generator_number
    )).scalar_one_or_none()
    if not detail:
        return "Archivo no encontrado.", 404
    stored_name = detail.water_image if kind == "water" else detail.oil_image
    try:
        storage = get_file_storage()
        key = resolve_fuel_key(storage, load_id, stored_name)
        return _file_response(storage, key, f"generador_{generator_number}_{kind}.png", "image/png", attachment=request.args.get("view") != "1")
    except StorageError:
        current_app.logger.exception("Error al recuperar fotografía de carga %s", load_id)
        return "No fue posible recuperar el archivo.", 503
