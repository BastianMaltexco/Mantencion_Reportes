"""Reglas de negocio compartidas para reportes de terreno y carga de petróleo."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal, InvalidOperation
import uuid

from flask import current_app
from werkzeug.datastructures import FileStorage
from werkzeug.utils import secure_filename

from app import db
from app.models import Attachment, FuelLoad, FuelLoadGenerator, Machinery, Report, ReportChecklist, Section
from app.services.storage import StorageError, fuel_key, get_file_storage, report_key


ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "pdf", "doc", "docx", "xls", "xlsx"}
IMAGE_EXTENSIONS = {"jpg", "jpeg", "png"}
MIME_BY_EXTENSION = {
    "jpg": {"image/jpeg", "image/pjpeg"}, "jpeg": {"image/jpeg", "image/pjpeg"}, "png": {"image/png"},
    "pdf": {"application/pdf"}, "doc": {"application/msword"},
    "docx": {"application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
    "xls": {"application/vnd.ms-excel"}, "xlsx": {"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"},
}
# Valores válidos únicamente para reportes nuevos. Los valores históricos se
# mantienen legibles en la base y en el Dashboard, pero no se vuelven a ofrecer.
SERVICE_TYPES = ("Correctiva", "Preventiva", "Predictiva", "Nueva instalación", "Otro")
CHECKLIST = (
    ("libre_obstrucciones", "Libre de elementos que pueden obstruir el trabajo?", "No"),
    ("componentes_mal_estado", "Piezas o componentes en mal estado?", "Si"),
    ("falla_constante", "Problema o falla es constante?", None),
    ("equipo_energizado", "Entrega de equipo energizado?", None),
    ("zona_limpia", "Zona de trabajo limpia?", "Si"),
    ("falla_solucionada", "Problema o falla solucionada?", None),
    ("protecciones_instaladas", "Protecciones instaladas?", None),
)
CHECKLIST_BY_KEY = {key: (question, evidence_answer) for key, question, evidence_answer in CHECKLIST}
VALID_ANSWERS = {"Si", "No", "No aplica"}


class BusinessRuleError(ValueError):
    """Error mostrado de manera consistente por la web y la API."""

    def __init__(self, message, code="validation_error", details=None):
        super().__init__(message)
        self.code = code
        self.details = details


def allowed_file(file: FileStorage):
    if not file or not file.filename or "." not in file.filename:
        return False
    extension = file.filename.rsplit(".", 1)[1].lower()
    return extension in ALLOWED_EXTENSIONS and file.mimetype in MIME_BY_EXTENSION[extension]


def image_file(file: FileStorage | None):
    return bool(allowed_file(file) and file.filename.rsplit(".", 1)[1].lower() in IMAGE_EXTENSIONS)


def validate_upload(file: FileStorage, *, image_only=False):
    valid = image_file(file) if image_only else allowed_file(file)
    if not valid:
        allowed = "JPG o PNG" if image_only else "JPG, PNG, PDF, Word o Excel"
        raise BusinessRuleError(f"Formato o tipo MIME no permitido. Use {allowed}.")
    stream = file.stream
    position = stream.tell()
    stream.seek(0, 2)
    size = stream.tell()
    stream.seek(position)
    if size <= 0 or size > current_app.config["MAX_CONTENT_LENGTH"]:
        raise BusinessRuleError("El archivo excede el límite permitido o está vacío.")
    return size


def parse_datetime(value, field_name):
    if isinstance(value, datetime):
        result = value
    elif isinstance(value, str) and value.strip():
        try:
            result = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError as error:
            raise BusinessRuleError(f"{field_name} debe ser una fecha y hora ISO-8601 válida.", details={field_name: "invalid"}) from error
    else:
        raise BusinessRuleError(f"{field_name} es obligatorio.", details={field_name: "required"})
    # Formularios HTML datetime-local no incluyen offset; se conserva la zona local
    # para compatibilidad con la web. Los clientes móviles deben enviar offset.
    if result.tzinfo is None:
        result = result.replace(tzinfo=datetime.now().astimezone().tzinfo)
    return result


def normalize_checklist(value):
    """Acepta dict web o lista JSON API y devuelve respuestas por clave."""
    if isinstance(value, dict):
        answers = {key: str(value.get(key, "")).strip() for key, _, _ in CHECKLIST}
    elif isinstance(value, list):
        answers = {}
        for item in value:
            if not isinstance(item, dict):
                raise BusinessRuleError("checklist debe contener objetos con key y answer.")
            key = str(item.get("key", "")).strip()
            if key in answers or key not in CHECKLIST_BY_KEY:
                raise BusinessRuleError("checklist contiene una pregunta inválida o repetida.")
            answers[key] = str(item.get("answer", "")).strip()
    else:
        raise BusinessRuleError("checklist es obligatorio.", details={"checklist": "required"})
    if set(answers) != set(CHECKLIST_BY_KEY) or any(answer not in VALID_ANSWERS for answer in answers.values()):
        raise BusinessRuleError("Responda todas las preguntas de entrega de equipo con Si, No o No aplica.")
    return answers


def _save_attachment(report_id, file, storage, created_keys):
    original_name = secure_filename(file.filename)
    if not original_name:
        raise BusinessRuleError("El nombre de un archivo no es válido.")
    extension = original_name.rsplit(".", 1)[1].lower()
    stored_name = report_key(report_id, f"{uuid.uuid4().hex}.{extension}")
    try:
        stored = storage.save(stored_name, file, file.mimetype)
    except StorageError as error:
        raise BusinessRuleError("No fue posible guardar el archivo.", code="storage_error") from error
    created_keys.append(stored.key)
    attachment = Attachment(
        report_id=report_id,
        original_name=original_name,
        stored_name=stored.key,
        mime_type=file.mimetype or "application/octet-stream",
        file_size=stored.size,
    )
    db.session.add(attachment)
    db.session.flush()
    return attachment


def create_maintenance_report(*, data, technician_id, evidence_files=None, attachments=None, upload_folder=None):
    """Crea un reporte sellado, con todas las reglas de validación web/API."""
    evidence_files = evidence_files or {}
    attachments = [item for item in (attachments or []) if item and item.filename]
    client = str(data.get("client", "")).strip()
    service_type = str(data.get("service_type", "")).strip()
    description = str(data.get("description", "")).strip()
    try:
        area_id = int(data.get("area_id"))
        section_id = int(data.get("section_id"))
        machinery_id = int(data.get("machinery_id"))
    except (TypeError, ValueError) as error:
        raise BusinessRuleError("Área, sección y maquinaria son obligatorias.") from error
    task_started_at = parse_datetime(data.get("task_started_at"), "task_started_at")
    task_finished_at = parse_datetime(data.get("task_finished_at"), "task_finished_at")
    answers = normalize_checklist(data.get("checklist"))
    machine = db.session.get(Machinery, machinery_id)
    section = db.session.get(Section, section_id)
    valid_asset = bool(machine and section and section.area_id == area_id and machine.section_id == section_id and machine.is_active and section.is_active)
    if not client or not description or service_type not in SERVICE_TYPES:
        raise BusinessRuleError("Complete los campos requeridos y seleccione un tipo de servicio válido.")
    if task_finished_at < task_started_at:
        raise BusinessRuleError("La finalización de tarea no puede ser anterior al comienzo.")
    if not valid_asset:
        raise BusinessRuleError("La selección de área, sección y maquinaria no es válida.")
    for item in attachments:
        validate_upload(item)
    required_evidence = [key for key, _, expected in CHECKLIST if expected and answers[key] == expected]
    missing_evidence = [key for key in required_evidence if not image_file(evidence_files.get(key))]
    if missing_evidence:
        raise BusinessRuleError(
            "Debe adjuntar una imagen JPG o PNG para cada respuesta que requiere evidencia.",
            code="evidence_required",
            details={"questions": missing_evidence},
        )
    for key in required_evidence:
        validate_upload(evidence_files[key], image_only=True)

    report = Report(
        client=client, location=None, service_type=service_type, description=description,
        technician_id=technician_id, area_id=area_id, section_id=section_id, machinery_id=machinery_id,
        task_started_at=task_started_at, task_finished_at=task_finished_at,
    )
    db.session.add(report)
    db.session.flush()
    storage = get_file_storage()
    created_keys = []
    try:
        evidence_ids = {}
        for key, question, expected_answer in CHECKLIST:
            evidence = evidence_files.get(key) if expected_answer else None
            if evidence and evidence.filename:
                evidence_ids[key] = _save_attachment(report.id, evidence, storage, created_keys).id
            db.session.add(ReportChecklist(
                report_id=report.id, question_key=key, question_text=question,
                answer=answers[key], evidence_attachment_id=evidence_ids.get(key),
            ))
        for attachment in attachments:
            _save_attachment(report.id, attachment, storage, created_keys)
        db.session.commit()
    except Exception:
        db.session.rollback()
        for key in created_keys:
            try:
                storage.delete(key)
            except StorageError:
                current_app.logger.exception("No se pudo limpiar un archivo no confirmado.")
        raise
    return report


def _decimal(value, field_name):
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError) as error:
        raise BusinessRuleError(f"{field_name} debe ser numérico.") from error


def create_fuel_load(*, data, technician_id, images=None, upload_folder=None):
    """Crea la carga de los dos generadores y exige las cuatro fotografías."""
    images = images or {}
    loaded_at = parse_datetime(data.get("loaded_at"), "loaded_at")
    generators = data.get("generators")
    if not isinstance(generators, list) or len(generators) != 2:
        raise BusinessRuleError("Debe informar exactamente los Generadores 1 y 2.")
    normalized = {}
    for generator in generators:
        if not isinstance(generator, dict):
            raise BusinessRuleError("Los datos de generadores no son válidos.")
        try:
            number = int(generator.get("number"))
        except (TypeError, ValueError) as error:
            raise BusinessRuleError("El número de generador no es válido.") from error
        if number not in {1, 2} or number in normalized:
            raise BusinessRuleError("Debe informar exactamente los Generadores 1 y 2.")
        liters = _decimal(generator.get("liters"), f"liters_{number}")
        hourmeter = _decimal(generator.get("hourmeter"), f"hourmeter_{number}")
        if liters < 0 or liters >= 750 or hourmeter < 0:
            raise BusinessRuleError("Los litros permitidos van de 0 a 749 y el horómetro no puede ser negativo.")
        normalized[number] = (liters, hourmeter)
    if set(normalized) != {1, 2} or any(not image_file(images.get((number, kind))) for number in (1, 2) for kind in ("water", "oil")):
        raise BusinessRuleError("Las cuatro fotografías JPG/PNG de nivel de agua y aceite son obligatorias.", code="evidence_required")
    for number in (1, 2):
        for kind in ("water", "oil"):
            validate_upload(images[(number, kind)], image_only=True)

    load = FuelLoad(technician_id=technician_id, loaded_at=loaded_at, observations=str(data.get("observations", "")).strip() or None)
    db.session.add(load)
    db.session.flush()
    storage = get_file_storage()
    created_keys = []
    try:
        for number, (liters, hourmeter) in normalized.items():
            saved_names = []
            for kind in ("water", "oil"):
                image = images[(number, kind)]
                original_name = secure_filename(image.filename)
                extension = original_name.rsplit(".", 1)[1].lower()
                stored_name = fuel_key(load.id, f"g{number}_{kind}_{uuid.uuid4().hex}.{extension}")
                try:
                    stored = storage.save(stored_name, image, image.mimetype)
                except StorageError as error:
                    raise BusinessRuleError("No fue posible guardar la fotografía.", code="storage_error") from error
                created_keys.append(stored.key)
                saved_names.append(stored.key)
            db.session.add(FuelLoadGenerator(
                load_id=load.id, generator_number=number, liters=liters, hourmeter=hourmeter,
                water_image=saved_names[0], oil_image=saved_names[1],
            ))
        db.session.commit()
    except Exception:
        db.session.rollback()
        for key in created_keys:
            try:
                storage.delete(key)
            except StorageError:
                current_app.logger.exception("No se pudo limpiar una fotografía no confirmada.")
        raise
    return load
