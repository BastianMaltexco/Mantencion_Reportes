USE [ReportesMantencion];
GO
CREATE TABLE dbo.CargasPetroleoGeneradores (CargaId INT IDENTITY PRIMARY KEY, TecnicoId INT NOT NULL FOREIGN KEY REFERENCES dbo.Usuarios(IdUsuario), FechaHoraCarga DATETIMEOFFSET(7) NOT NULL, Observaciones NVARCHAR(MAX) NULL, CreadoEn DATETIMEOFFSET(7) NOT NULL DEFAULT SYSDATETIMEOFFSET());
CREATE TABLE dbo.CargasPetroleoGeneradorDetalle (DetalleId INT IDENTITY PRIMARY KEY, CargaId INT NOT NULL FOREIGN KEY REFERENCES dbo.CargasPetroleoGeneradores(CargaId), NumeroGenerador INT NOT NULL CHECK (NumeroGenerador IN (1,2)), Litros DECIMAL(8,2) NOT NULL CHECK (Litros >= 0 AND Litros < 750), Horometro DECIMAL(12,2) NOT NULL CHECK (Horometro >= 0), ImagenNivelAgua NVARCHAR(255) NOT NULL, ImagenNivelAceite NVARCHAR(255) NOT NULL, CONSTRAINT UQ_Carga_Generador UNIQUE(CargaId,NumeroGenerador));
GO
