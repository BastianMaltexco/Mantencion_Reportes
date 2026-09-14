from pathlib import Path
import uuid
from datetime import datetime

from flask import Blueprint, current_app, flash, jsonify, redirect, render_template, request, send_from_directory, session, url_for
from sqlalchemy import func, select
from werkzeug.datastructures import FileStorage
from werkzeug.utils import secure_filename

from app import db, login_required
from app.models import Area, Attachment, FuelLoad, FuelLoadGenerator, Machinery, Report, ReportChecklist, Section, User

reports_bp = Blueprint("reports", __name__)
ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "pdf", "doc", "docx", "xls", "xlsx"}
IMAGE_EXTENSIONS = {"jpg", "jpeg", "png"}
SERVICE_TYPES = ("Mantenimiento Preventivo", "Correctivo", "Inspección", "Instalación")
CHECKLIST = (
    ("libre_obstrucciones", "Libre de elementos que pueden obstruir el trabajo?", "No"),
    ("componentes_mal_estado", "Piezas o componentes en mal estado?", "Si"),
    ("falla_constante", "Problema o falla es constante?", None),
    ("equipo_energizado", "Entrega de equipo energizado?", None),
    ("zona_limpia", "Zona de trabajo limpia?", "Si"),
    ("falla_solucionada", "Problema o falla solucionada?", None),
    ("protecciones_instaladas", "Protecciones instaladas?", None),
)


def _allowed(file: FileStorage):
    return "." in file.filename and file.filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def _image(file: FileStorage | None):
    return file and file.filename and "." in file.filename and file.filename.rsplit(".", 1)[1].lower() in IMAGE_EXTENSIONS


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
    record_type = request.args.get("record_type", "maintenance")
    if record_type == "fuel":
        query = select(FuelLoad).order_by(FuelLoad.loaded_at.desc())
        if request.args.get("technician_id", type=int): query = query.where(FuelLoad.technician_id == request.args.get("technician_id", type=int))
        if request.args.get("date_from"): query = query.where(FuelLoad.loaded_at >= request.args["date_from"])
        fuel_loads = db.session.execute(query).scalars().all()
        counts = {}
        for load in fuel_loads:
            user = db.session.get(User, load.technician_id); counts[user.full_name] = counts.get(user.full_name, 0) + 1
        technicians = db.session.execute(select(User).where(User.is_active == True).order_by(User.full_name)).scalars().all()  # noqa: E712
        return render_template("metrics_dashboard.html", record_type=record_type, fuel_loads=fuel_loads, reports=[], total=len(fuel_loads), by_user=sorted(counts.items(), key=lambda x:x[1], reverse=True), by_service={"Carga de petróleo":len(fuel_loads)}, by_machine={}, by_date={x.loaded_at.strftime("%d-%m"): sum(1 for y in fuel_loads if y.loaded_at.strftime("%d-%m")==x.loaded_at.strftime("%d-%m")) for x in fuel_loads}, technicians=technicians, areas=[], sections=[], machines=[])
    reports = db.session.execute(_filtered_reports().order_by(Report.created_at.desc())).scalars().all()
    counts = {}
    for report in reports:
        counts[report.technician.full_name] = counts.get(report.technician.full_name, 0) + 1
    service_counts, machine_counts, date_counts = {}, {}, {}
    for report in reports:
        service_counts[report.service_type] = service_counts.get(report.service_type, 0) + 1
        machine = report.machinery.name if report.machinery else "Sin maquinaria"
        machine_counts[machine] = machine_counts.get(machine, 0) + 1
        day = report.created_at.strftime("%d-%m") if report.created_at else "Sin fecha"
        date_counts[day] = date_counts.get(day, 0) + 1
    technicians = db.session.execute(select(User).where(User.is_active == True).order_by(User.full_name)).scalars().all()  # noqa: E712
    return render_template("metrics_dashboard.html", record_type=record_type, fuel_loads=[], reports=reports, total=len(reports), by_user=sorted(counts.items(), key=lambda x: x[1], reverse=True), by_service=service_counts, by_machine=sorted(machine_counts.items(), key=lambda x: x[1], reverse=True)[:8], by_date=date_counts, technicians=technicians, areas=db.session.execute(select(Area).order_by(Area.name)).scalars().all(), sections=db.session.execute(select(Section).order_by(Section.name)).scalars().all(), machines=db.session.execute(select(Machinery).order_by(Machinery.name)).scalars().all())


@reports_bp.get("/reports/new")
@login_required
def choose_report():
    return render_template("choose_report.html")

@reports_bp.route("/reports/maintenance/new", methods=["GET", "POST"])
@login_required
def create_report():
    if request.method == "POST":
        client = request.form.get("client", "").strip()
        service_type = request.form.get("service_type", "")
        description = request.form.get("description", "").strip()
        area_id = request.form.get("area_id", type=int)
        section_id = request.form.get("section_id", type=int)
        machinery_id = request.form.get("machinery_id", type=int)
        started_raw = request.form.get("task_started_at", "")
        finished_raw = request.form.get("task_finished_at", "")
        try:
            local_tz = datetime.now().astimezone().tzinfo
            task_started_at = datetime.fromisoformat(started_raw).replace(tzinfo=local_tz) if started_raw else None
            task_finished_at = datetime.fromisoformat(finished_raw).replace(tzinfo=local_tz) if finished_raw else None
        except ValueError:
            task_started_at = task_finished_at = None
        files = [f for f in request.files.getlist("attachments") if f and f.filename]
        invalid = [f.filename for f in files if not _allowed(f)]
        answers = {key: request.form.get(f"check_{key}", "") for key, _, _ in CHECKLIST}
        evidence_files = {key: request.files.get(f"evidence_{key}") for key, _, required_answer in CHECKLIST if required_answer}
        machine = db.session.get(Machinery, machinery_id) if machinery_id else None
        section = db.session.get(Section, section_id) if section_id else None
        valid_asset = machine and section and section.area_id == area_id and machine.section_id == section_id and machine.is_active and section.is_active
        if not all((client, description, area_id, section_id, machinery_id, task_started_at, task_finished_at)) or service_type not in SERVICE_TYPES:
            flash("Complete los campos requeridos y seleccione un tipo de servicio válido.", "error")
        elif task_finished_at < task_started_at:
            flash("La finalización de tarea no puede ser anterior al comienzo.", "error")
        elif not valid_asset:
            flash("La selección de área, sección y maquinaria no es válida.", "error")
        elif any(answer not in {"Si", "No", "No aplica"} for answer in answers.values()):
            flash("Responda todas las preguntas de entrega de equipo.", "error")
        elif any(answers[key] == required_answer and not _image(evidence_files[key]) for key, _, required_answer in CHECKLIST if required_answer):
            flash("Debe adjuntar una imagen JPG o PNG para cada respuesta que requiere evidencia.", "error")
        elif invalid:
            flash("Formato no permitido: " + ", ".join(invalid), "error")
        else:
            report = Report(client=client, location=None, service_type=service_type, description=description,
                            technician_id=session["user_id"], area_id=area_id, section_id=section_id, machinery_id=machinery_id)
            report.task_started_at = task_started_at
            report.task_finished_at = task_finished_at
            db.session.add(report)
            db.session.flush()
            report_folder = Path(current_app.config["UPLOAD_FOLDER"]) / str(report.id)
            report_folder.mkdir(parents=True, exist_ok=True)
            evidence_attachment_ids = {}
            for key, question, required_answer in CHECKLIST:
                evidence = evidence_files.get(key) if required_answer else None
                if evidence and evidence.filename:
                    original_name = secure_filename(evidence.filename)
                    extension = original_name.rsplit(".", 1)[1].lower()
                    stored_name = f"{uuid.uuid4().hex}.{extension}"
                    target = report_folder / stored_name
                    evidence.save(target)
                    attachment = Attachment(report_id=report.id, original_name=original_name, stored_name=stored_name,
                                            mime_type=evidence.mimetype or "application/octet-stream", file_size=target.stat().st_size)
                    db.session.add(attachment)
                    db.session.flush()
                    evidence_attachment_ids[key] = attachment.id
                db.session.add(ReportChecklist(report_id=report.id, question_key=key, question_text=question, answer=answers[key], evidence_attachment_id=evidence_attachment_ids.get(key)))
            for file in files:
                original_name = secure_filename(file.filename)
                extension = original_name.rsplit(".", 1)[1].lower()
                stored_name = f"{uuid.uuid4().hex}.{extension}"
                target = report_folder / stored_name
                file.save(target)
                db.session.add(Attachment(report_id=report.id, original_name=original_name, stored_name=stored_name,
                                          mime_type=file.mimetype or "application/octet-stream", file_size=target.stat().st_size))
            db.session.commit()
            flash("Reporte registrado y sellado con la hora del servidor.", "success")
            return redirect(url_for("reports.report_detail", report_id=report.id))
    return render_template("create_report.html", service_types=SERVICE_TYPES, checklist=CHECKLIST)

@reports_bp.route("/reports/fuel/new", methods=["GET", "POST"])
@login_required
def create_fuel_load():
    if request.method == "POST":
        try:
            loaded_at = datetime.fromisoformat(request.form["loaded_at"]).replace(tzinfo=datetime.now().astimezone().tzinfo)
            values = [(n, float(request.form[f"liters_{n}"]), float(request.form[f"hourmeter_{n}"])) for n in (1, 2)]
        except (KeyError, ValueError):
            flash("Complete fecha, litros y horómetros con valores válidos.", "error"); return render_template("fuel_load.html")
        images = {(n, kind): request.files.get(f"{kind}_{n}") for n in (1,2) for kind in ("water", "oil")}
        if any(l < 0 or l > 749 or h < 0 for _, l, h in values) or any(not _image(f) for f in images.values()):
            flash("Los litros permitidos van de 0 a 749 y las cuatro fotografías JPG/PNG son obligatorias.", "error"); return render_template("fuel_load.html")
        load = FuelLoad(technician_id=session["user_id"], loaded_at=loaded_at, observations=request.form.get("observations", "").strip() or None)
        db.session.add(load); db.session.flush(); folder = Path(current_app.config["UPLOAD_FOLDER"]) / "fuel" / str(load.id); folder.mkdir(parents=True, exist_ok=True)
        for n, liters, hourmeter in values:
            names=[]
            for kind in ("water","oil"):
                f=images[(n,kind)]; ext=secure_filename(f.filename).rsplit('.',1)[1].lower(); name=f"g{n}_{kind}_{uuid.uuid4().hex}.{ext}"; f.save(folder/name); names.append(name)
            db.session.add(FuelLoadGenerator(load_id=load.id,generator_number=n,liters=liters,hourmeter=hourmeter,water_image=names[0],oil_image=names[1]))
        db.session.commit(); flash("Carga de petróleo registrada.", "success"); return redirect(url_for("reports.dashboard"))
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
    folder = Path(current_app.config["UPLOAD_FOLDER"]) / str(attachment.report_id)
    return send_from_directory(folder, attachment.stored_name, as_attachment=True, download_name=attachment.original_name)
