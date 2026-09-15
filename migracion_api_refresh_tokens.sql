/*
  Etapas 1-2 API móvil. Ejecutar una vez en ReportesMantencion o
  ReportesMantencionTest. Es aditivo: no modifica tablas ni datos existentes.
*/
IF OBJECT_ID(N'dbo.ApiRefreshTokens', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ApiRefreshTokens (
        ApiRefreshTokenId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ApiRefreshTokens PRIMARY KEY,
        UsuarioId INT NOT NULL,
        TokenHash CHAR(64) NOT NULL,
        EmitidoEn DATETIMEOFFSET(7) NOT NULL,
        ExpiraEn DATETIMEOFFSET(7) NOT NULL,
        RevocadoEn DATETIMEOFFSET(7) NULL,
        ReemplazadoEn DATETIMEOFFSET(7) NULL,
        Cliente NVARCHAR(100) NULL,
        CONSTRAINT FK_ApiRefreshTokens_Usuarios FOREIGN KEY (UsuarioId)
            REFERENCES dbo.Usuarios(IdUsuario),
        CONSTRAINT UQ_ApiRefreshTokens_TokenHash UNIQUE (TokenHash),
        CONSTRAINT CK_ApiRefreshTokens_Fechas CHECK (ExpiraEn > EmitidoEn)
    );
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.ApiRefreshTokens')
      AND name = N'IX_ApiRefreshTokens_Usuario_Expira'
)
    CREATE INDEX IX_ApiRefreshTokens_Usuario_Expira
        ON dbo.ApiRefreshTokens(UsuarioId, ExpiraEn);
GO
