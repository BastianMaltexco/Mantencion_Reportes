from app import db
from sqlalchemy import CheckConstraint, ForeignKey, Index, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import DateTime, String, Text, Boolean, Integer


class Role(db.Model):
    __tablename__ = "Roles"
    __table_args__ = {"schema": "dbo"}
    id: Mapped[int] = mapped_column("RolId", Integer, primary_key=True)
    name: Mapped[str] = mapped_column("Nombre", String(50), unique=True, nullable=False)


class User(db.Model):
    __tablename__ = "Usuarios"
    __table_args__ = {"schema": "dbo"}
    # Esta tabla ya existía en ReportesMantencion; los nombres se respetan tal cual.
    id: Mapped[int] = mapped_column("IdUsuario", Integer, primary_key=True)
    username: Mapped[str] = mapped_column("CorreoElectronico", String(255), unique=True, nullable=False)
    full_name: Mapped[str] = mapped_column("NombreCompleto", String(150), nullable=False)
    password_hash: Mapped[str] = mapped_column("ContrasenaHash", String(510), nullable=False)
    role: Mapped[str] = mapped_column("Rol", String(40), nullable=False)
    is_active: Mapped[bool] = mapped_column("Activo", Boolean, nullable=False, server_default="1")
    created_at: Mapped[object] = mapped_column("FechaCreacion", DateTime, server_default=func.getdate())
    reports: Mapped[list["Report"]] = relationship(back_populates="technician")


class Report(db.Model):
    __tablename__ = "Reportes"
    __table_args__ = (
        CheckConstraint("TipoServicio IN ('Mantenimiento Preventivo', 'Correctivo', 'Inspección', 'Instalación')", name="CK_Reportes_TipoServicio"),
        Index("IX_Reportes_CreadoEn", "CreadoEn"), Index("IX_Reportes_Cliente", "Cliente"),
        {"schema": "dbo"},
    )
    id: Mapped[int] = mapped_column("ReporteId", Integer, primary_key=True)
    client: Mapped[str] = mapped_column("Cliente", String(150), nullable=False)
    location: Mapped[str | None] = mapped_column("Ubicacion", String(200), nullable=True)
    service_type: Mapped[str] = mapped_column("TipoServicio", String(50), nullable=False)
    description: Mapped[str] = mapped_column("Descripcion", Text, nullable=False)
    technician_id: Mapped[int] = mapped_column("TecnicoId", ForeignKey("dbo.Usuarios.IdUsuario"), nullable=False)
    area_id: Mapped[int | None] = mapped_column("AreaId", ForeignKey("dbo.Areas.AreaId"), nullable=True)
    section_id: Mapped[int | None] = mapped_column("SeccionId", ForeignKey("dbo.Secciones.SeccionId"), nullable=True)
    machinery_id: Mapped[int | None] = mapped_column("MaquinariaId", ForeignKey("dbo.Maquinarias.MaquinariaId"), nullable=True)
    task_started_at: Mapped[object | None] = mapped_column("ComienzoTarea", DateTime(timezone=True), nullable=True)
    task_finished_at: Mapped[object | None] = mapped_column("FinalizacionTarea", DateTime(timezone=True), nullable=True)
    # Solo default de servidor: nunca se acepta desde formularios ni se actualiza.
    created_at: Mapped[object] = mapped_column("CreadoEn", DateTime(timezone=True), nullable=False, server_default=func.sysdatetimeoffset())
    technician: Mapped[User] = relationship(back_populates="reports")
    attachments: Mapped[list["Attachment"]] = relationship(back_populates="report", cascade="all, delete-orphan")
    area: Mapped["Area | None"] = relationship(foreign_keys=[area_id])
    section: Mapped["Section | None"] = relationship(foreign_keys=[section_id])
    machinery: Mapped["Machinery | None"] = relationship(foreign_keys=[machinery_id])


class Area(db.Model):
    __tablename__ = "Areas"
    __table_args__ = {"schema": "dbo"}
    id: Mapped[int] = mapped_column("AreaId", Integer, primary_key=True)
    name: Mapped[str] = mapped_column("Nombre", String(300), nullable=False)
    is_active: Mapped[bool] = mapped_column("Activo", Boolean, nullable=False)


class Section(db.Model):
    __tablename__ = "Secciones"
    __table_args__ = {"schema": "dbo"}
    id: Mapped[int] = mapped_column("SeccionId", Integer, primary_key=True)
    area_id: Mapped[int] = mapped_column("AreaId", ForeignKey("dbo.Areas.AreaId"), nullable=False)
    name: Mapped[str] = mapped_column("Nombre", String(300), nullable=False)
    is_active: Mapped[bool] = mapped_column("Activo", Boolean, nullable=False)


class Machinery(db.Model):
    __tablename__ = "Maquinarias"
    __table_args__ = {"schema": "dbo"}
    id: Mapped[int] = mapped_column("MaquinariaId", Integer, primary_key=True)
    section_id: Mapped[int] = mapped_column("SeccionId", ForeignKey("dbo.Secciones.SeccionId"), nullable=False)
    source_code: Mapped[int | None] = mapped_column("CodigoOrigen", Integer, nullable=True)
    name: Mapped[str] = mapped_column("Nombre", String(500), nullable=False)
    is_active: Mapped[bool] = mapped_column("Activo", Boolean, nullable=False)


class Attachment(db.Model):
    __tablename__ = "Adjuntos"
    __table_args__ = (Index("IX_Adjuntos_ReporteId", "ReporteId"), {"schema": "dbo"})
    id: Mapped[int] = mapped_column("AdjuntoId", Integer, primary_key=True)
    report_id: Mapped[int] = mapped_column("ReporteId", ForeignKey("dbo.Reportes.ReporteId"), nullable=False)
    original_name: Mapped[str] = mapped_column("NombreOriginal", String(255), nullable=False)
    stored_name: Mapped[str] = mapped_column("NombreAlmacenado", String(255), unique=True, nullable=False)
    mime_type: Mapped[str] = mapped_column("TipoMime", String(100), nullable=False)
    file_size: Mapped[int] = mapped_column("TamanoBytes", Integer, nullable=False)
    uploaded_at: Mapped[object] = mapped_column("SubidoEn", DateTime(timezone=True), nullable=False, server_default=func.sysdatetimeoffset())
    report: Mapped[Report] = relationship(back_populates="attachments")


class ReportChecklist(db.Model):
    __tablename__ = "ReporteChecklist"
    __table_args__ = {"schema": "dbo"}
    id: Mapped[int] = mapped_column("ReporteChecklistId", Integer, primary_key=True)
    report_id: Mapped[int] = mapped_column("ReporteId", ForeignKey("dbo.Reportes.ReporteId"), nullable=False)
    question_key: Mapped[str] = mapped_column("ClavePregunta", String(80), nullable=False)
    question_text: Mapped[str] = mapped_column("Pregunta", String(300), nullable=False)
    answer: Mapped[str] = mapped_column("Respuesta", String(15), nullable=False)
    evidence_attachment_id: Mapped[int | None] = mapped_column("AdjuntoEvidenciaId", ForeignKey("dbo.Adjuntos.AdjuntoId"), nullable=True)

class FuelLoad(db.Model):
    __tablename__ = "CargasPetroleoGeneradores"
    __table_args__ = {"schema": "dbo"}
    id: Mapped[int] = mapped_column("CargaId", Integer, primary_key=True)
    technician_id: Mapped[int] = mapped_column("TecnicoId", ForeignKey("dbo.Usuarios.IdUsuario"), nullable=False)
    loaded_at: Mapped[object] = mapped_column("FechaHoraCarga", DateTime(timezone=True), nullable=False)
    observations: Mapped[str | None] = mapped_column("Observaciones", Text, nullable=True)
    created_at: Mapped[object] = mapped_column("CreadoEn", DateTime(timezone=True), server_default=func.sysdatetimeoffset())

class FuelLoadGenerator(db.Model):
    __tablename__ = "CargasPetroleoGeneradorDetalle"
    __table_args__ = {"schema": "dbo"}
    id: Mapped[int] = mapped_column("DetalleId", Integer, primary_key=True)
    load_id: Mapped[int] = mapped_column("CargaId", ForeignKey("dbo.CargasPetroleoGeneradores.CargaId"), nullable=False)
    generator_number: Mapped[int] = mapped_column("NumeroGenerador", Integer, nullable=False)
    liters: Mapped[float] = mapped_column("Litros", db.Numeric(8, 2), nullable=False)
    hourmeter: Mapped[float] = mapped_column("Horometro", db.Numeric(12, 2), nullable=False)
    water_image: Mapped[str] = mapped_column("ImagenNivelAgua", String(255), nullable=False)
    oil_image: Mapped[str] = mapped_column("ImagenNivelAceite", String(255), nullable=False)
