/* Reportes Mantención - SQL Server 2019+.
   Ejecute este script sobre la base ReportesMantencion antes de iniciar Flask. */
USE [ReportesMantencion];
GO

IF OBJECT_ID(N'dbo.Roles', N'U') IS NULL
CREATE TABLE dbo.Roles (
    RolId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Roles PRIMARY KEY,
    Nombre NVARCHAR(50) NOT NULL CONSTRAINT UQ_Roles_Nombre UNIQUE
);
GO
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE Nombre = N'Administrador') INSERT dbo.Roles (Nombre) VALUES (N'Administrador');
IF NOT EXISTS (SELECT 1 FROM dbo.Roles WHERE Nombre = N'Técnico') INSERT dbo.Roles (Nombre) VALUES (N'Técnico');
GO

IF OBJECT_ID(N'dbo.Usuarios', N'U') IS NULL
CREATE TABLE dbo.Usuarios (
    IdUsuario INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Usuarios PRIMARY KEY,
    NombreCompleto NVARCHAR(300) NOT NULL,
    CorreoElectronico NVARCHAR(510) NOT NULL CONSTRAINT UQ_Usuarios_CorreoElectronico UNIQUE,
    ContrasenaHash NVARCHAR(510) NOT NULL,
    Rol NVARCHAR(40) NOT NULL,
    Activo BIT NOT NULL CONSTRAINT DF_Usuarios_Activo DEFAULT (1),
    FechaCreacion DATETIME2 NOT NULL CONSTRAINT DF_Usuarios_FechaCreacion DEFAULT (SYSDATETIME()),
    FechaActualizacion DATETIME2 NULL
);
GO

IF OBJECT_ID(N'dbo.Reportes', N'U') IS NULL
CREATE TABLE dbo.Reportes (
    ReporteId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Reportes PRIMARY KEY,
    Cliente NVARCHAR(150) NOT NULL,
    Ubicacion NVARCHAR(200) NOT NULL,
    TipoServicio NVARCHAR(50) NOT NULL,
    Descripcion NVARCHAR(MAX) NOT NULL,
    TecnicoId INT NOT NULL,
    /* Esta columna no se expone a edicion desde la aplicación. */
    CreadoEn DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_Reportes_CreadoEn DEFAULT (SYSDATETIMEOFFSET()),
    CONSTRAINT CK_Reportes_TipoServicio CHECK (TipoServicio IN (N'Correctiva', N'Preventiva', N'Predictiva', N'Nueva instalación', N'Otro')),
    CONSTRAINT FK_Reportes_Usuarios FOREIGN KEY (TecnicoId) REFERENCES dbo.Usuarios(IdUsuario)
);
GO

IF OBJECT_ID(N'dbo.Adjuntos', N'U') IS NULL
CREATE TABLE dbo.Adjuntos (
    AdjuntoId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Adjuntos PRIMARY KEY,
    ReporteId INT NOT NULL,
    NombreOriginal NVARCHAR(255) NOT NULL,
    NombreAlmacenado NVARCHAR(255) NOT NULL CONSTRAINT UQ_Adjuntos_NombreAlmacenado UNIQUE,
    TipoMime NVARCHAR(100) NOT NULL,
    TamanoBytes INT NOT NULL CONSTRAINT CK_Adjuntos_Tamano CHECK (TamanoBytes >= 0),
    SubidoEn DATETIMEOFFSET(7) NOT NULL CONSTRAINT DF_Adjuntos_SubidoEn DEFAULT (SYSDATETIMEOFFSET()),
    CONSTRAINT FK_Adjuntos_Reportes FOREIGN KEY (ReporteId) REFERENCES dbo.Reportes(ReporteId)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Reportes_CreadoEn' AND object_id = OBJECT_ID(N'dbo.Reportes')) CREATE INDEX IX_Reportes_CreadoEn ON dbo.Reportes(CreadoEn DESC);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Reportes_Cliente' AND object_id = OBJECT_ID(N'dbo.Reportes')) CREATE INDEX IX_Reportes_Cliente ON dbo.Reportes(Cliente);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Reportes_TecnicoId' AND object_id = OBJECT_ID(N'dbo.Reportes')) CREATE INDEX IX_Reportes_TecnicoId ON dbo.Reportes(TecnicoId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Adjuntos_ReporteId' AND object_id = OBJECT_ID(N'dbo.Adjuntos')) CREATE INDEX IX_Adjuntos_ReporteId ON dbo.Adjuntos(ReporteId);
GO
