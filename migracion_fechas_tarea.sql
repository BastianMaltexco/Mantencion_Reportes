/* Ejecutar una vez en ReportesMantencion. Los reportes antiguos mantienen NULL. */
USE [ReportesMantencion];
GO
IF COL_LENGTH(N'dbo.Reportes', N'ComienzoTarea') IS NULL
    ALTER TABLE dbo.Reportes ADD ComienzoTarea DATETIMEOFFSET(7) NULL;
IF COL_LENGTH(N'dbo.Reportes', N'FinalizacionTarea') IS NULL
    ALTER TABLE dbo.Reportes ADD FinalizacionTarea DATETIMEOFFSET(7) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Reportes_ComienzoTarea' AND object_id = OBJECT_ID(N'dbo.Reportes'))
    CREATE INDEX IX_Reportes_ComienzoTarea ON dbo.Reportes(ComienzoTarea);
GO
