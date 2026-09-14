/* Ejecutar una vez en ReportesMantencion antes de usar los nuevos selectores. */
USE [ReportesMantencion];
GO

IF COL_LENGTH(N'dbo.Reportes', N'AreaId') IS NULL
    ALTER TABLE dbo.Reportes ADD AreaId INT NULL;
IF COL_LENGTH(N'dbo.Reportes', N'SeccionId') IS NULL
    ALTER TABLE dbo.Reportes ADD SeccionId INT NULL;
IF COL_LENGTH(N'dbo.Reportes', N'MaquinariaId') IS NULL
    ALTER TABLE dbo.Reportes ADD MaquinariaId INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Reportes_Areas')
    ALTER TABLE dbo.Reportes ADD CONSTRAINT FK_Reportes_Areas FOREIGN KEY (AreaId) REFERENCES dbo.Areas(AreaId);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Reportes_Secciones')
    ALTER TABLE dbo.Reportes ADD CONSTRAINT FK_Reportes_Secciones FOREIGN KEY (SeccionId) REFERENCES dbo.Secciones(SeccionId);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Reportes_Maquinarias')
    ALTER TABLE dbo.Reportes ADD CONSTRAINT FK_Reportes_Maquinarias FOREIGN KEY (MaquinariaId) REFERENCES dbo.Maquinarias(MaquinariaId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Reportes_AreaId' AND object_id = OBJECT_ID(N'dbo.Reportes'))
    CREATE INDEX IX_Reportes_AreaId ON dbo.Reportes(AreaId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Reportes_SeccionId' AND object_id = OBJECT_ID(N'dbo.Reportes'))
    CREATE INDEX IX_Reportes_SeccionId ON dbo.Reportes(SeccionId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Reportes_MaquinariaId' AND object_id = OBJECT_ID(N'dbo.Reportes'))
    CREATE INDEX IX_Reportes_MaquinariaId ON dbo.Reportes(MaquinariaId);
GO
