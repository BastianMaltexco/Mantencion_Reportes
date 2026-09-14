/* Ejecutar una vez en ReportesMantencion antes de activar el checklist. */
USE [ReportesMantencion];
GO

IF OBJECT_ID(N'dbo.ReporteChecklist', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ReporteChecklist (
        ReporteChecklistId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        ReporteId INT NOT NULL,
        ClavePregunta NVARCHAR(80) NOT NULL,
        Pregunta NVARCHAR(300) NOT NULL,
        Respuesta NVARCHAR(15) NOT NULL,
        AdjuntoEvidenciaId INT NULL,
        CONSTRAINT CK_ReporteChecklist_Respuesta CHECK (Respuesta IN (N'Si', N'No', N'No aplica')),
        CONSTRAINT FK_ReporteChecklist_Reportes FOREIGN KEY (ReporteId) REFERENCES dbo.Reportes(ReporteId),
        CONSTRAINT FK_ReporteChecklist_Adjuntos FOREIGN KEY (AdjuntoEvidenciaId) REFERENCES dbo.Adjuntos(AdjuntoId),
        CONSTRAINT UQ_ReporteChecklist_Reporte_Pregunta UNIQUE (ReporteId, ClavePregunta)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ReporteChecklist_ReporteId' AND object_id = OBJECT_ID(N'dbo.ReporteChecklist'))
    CREATE INDEX IX_ReporteChecklist_ReporteId ON dbo.ReporteChecklist(ReporteId);
GO
