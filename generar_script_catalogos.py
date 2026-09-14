"""Genera el DDL y los datos de catálogo desde la hoja 'hoja concat'."""
from pathlib import Path
import sys

import openpyxl


def sql_text(value: str) -> str:
    return "N'" + value.replace("'", "''") + "'"


def main(source: Path, output: Path) -> None:
    workbook = openpyxl.load_workbook(source, read_only=True, data_only=True)
    sheet = workbook["hoja concat"]
    rows = []
    for source_id, area, section, machine in sheet.iter_rows(min_row=2, values_only=True):
        if all((area, section, machine)):
            rows.append((None if source_id is None else int(source_id), str(area).strip(), str(section).strip(), str(machine).strip()))
    if not rows:
        raise ValueError("La hoja 'hoja concat' no contiene filas completas.")

    values = ",\n        ".join(
        f"({'NULL' if source_id is None else source_id}, {sql_text(area)}, {sql_text(section)}, {sql_text(machine)})"
        for source_id, area, section, machine in rows
    )
    sql = f"""/*
  Catálogos Área → Sección → Maquinaria
  Fuente: hoja 'hoja concat' de libro DatasCOPE.xlsx.
  Registros importados: {len(rows)}.
*/
USE [ReportesMantencion];
GO
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Areas', N'U') IS NULL
BEGIN
    EXEC(N'CREATE TABLE dbo.Areas (
        AreaId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Nombre NVARCHAR(300) NOT NULL,
        Activo BIT NOT NULL DEFAULT (1),
        CreadoEn DATETIMEOFFSET(7) NOT NULL DEFAULT (SYSDATETIMEOFFSET()),
        UNIQUE (Nombre)
    )');
END;
GO

IF OBJECT_ID(N'dbo.Secciones', N'U') IS NULL
BEGIN
    EXEC(N'CREATE TABLE dbo.Secciones (
        SeccionId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        AreaId INT NOT NULL REFERENCES dbo.Areas(AreaId),
        Nombre NVARCHAR(300) NOT NULL,
        Activo BIT NOT NULL DEFAULT (1),
        CreadoEn DATETIMEOFFSET(7) NOT NULL DEFAULT (SYSDATETIMEOFFSET()),
        UNIQUE (AreaId, Nombre)
    )');
END;
GO

IF OBJECT_ID(N'dbo.Maquinarias', N'U') IS NULL
BEGIN
    EXEC(N'CREATE TABLE dbo.Maquinarias (
        MaquinariaId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        SeccionId INT NOT NULL REFERENCES dbo.Secciones(SeccionId),
        CodigoOrigen INT NULL,
        Nombre NVARCHAR(500) NOT NULL,
        Activo BIT NOT NULL DEFAULT (1),
        CreadoEn DATETIMEOFFSET(7) NOT NULL DEFAULT (SYSDATETIMEOFFSET())
    )');
END;
GO

/* Compatibilidad con una ejecución anterior de este script que exigía código
   y nombre únicos. La fuente contiene dos códigos vacíos y nombres repetidos. */
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = N'UQ_Maquinarias_CodigoOrigen' AND parent_object_id = OBJECT_ID(N'dbo.Maquinarias'))
    ALTER TABLE dbo.Maquinarias DROP CONSTRAINT UQ_Maquinarias_CodigoOrigen;
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = N'UQ_Maquinarias_Seccion_Nombre' AND parent_object_id = OBJECT_ID(N'dbo.Maquinarias'))
    ALTER TABLE dbo.Maquinarias DROP CONSTRAINT UQ_Maquinarias_Seccion_Nombre;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Maquinarias_CodigoOrigen' AND object_id = OBJECT_ID(N'dbo.Maquinarias'))
    DROP INDEX UX_Maquinarias_CodigoOrigen ON dbo.Maquinarias;
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.Maquinarias') AND name = N'CodigoOrigen' AND is_nullable = 0
)
    ALTER TABLE dbo.Maquinarias ALTER COLUMN CodigoOrigen INT NULL;
GO

BEGIN TRANSACTION;
DECLARE @Fuente TABLE (
    CodigoOrigen INT NULL,
    AreaNombre NVARCHAR(300) NOT NULL,
    SeccionNombre NVARCHAR(300) NOT NULL,
    MaquinariaNombre NVARCHAR(500) NOT NULL
);
INSERT INTO @Fuente (CodigoOrigen, AreaNombre, SeccionNombre, MaquinariaNombre)
VALUES
        {values};

INSERT INTO dbo.Areas (Nombre)
SELECT DISTINCT f.AreaNombre
FROM @Fuente AS f
WHERE NOT EXISTS (SELECT 1 FROM dbo.Areas AS a WHERE a.Nombre = f.AreaNombre);

INSERT INTO dbo.Secciones (AreaId, Nombre)
SELECT DISTINCT a.AreaId, f.SeccionNombre
FROM @Fuente AS f
INNER JOIN dbo.Areas AS a ON a.Nombre = f.AreaNombre
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Secciones AS s
    WHERE s.AreaId = a.AreaId AND s.Nombre = f.SeccionNombre
);

INSERT INTO dbo.Maquinarias (SeccionId, CodigoOrigen, Nombre)
SELECT s.SeccionId, f.CodigoOrigen, f.MaquinariaNombre
FROM @Fuente AS f
INNER JOIN dbo.Areas AS a ON a.Nombre = f.AreaNombre
INNER JOIN dbo.Secciones AS s ON s.AreaId = a.AreaId AND s.Nombre = f.SeccionNombre
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Maquinarias AS m
    WHERE (m.CodigoOrigen = f.CodigoOrigen)
       OR (m.CodigoOrigen IS NULL AND f.CodigoOrigen IS NULL AND m.Nombre = f.MaquinariaNombre AND m.SeccionId = s.SeccionId)
);
COMMIT TRANSACTION;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Maquinarias_CodigoOrigen' AND object_id = OBJECT_ID(N'dbo.Maquinarias'))
    CREATE UNIQUE INDEX UX_Maquinarias_CodigoOrigen ON dbo.Maquinarias(CodigoOrigen) WHERE CodigoOrigen IS NOT NULL;
GO

CREATE OR ALTER VIEW dbo.vw_AreaSeccionMaquinaria
AS
SELECT
    a.AreaId,
    a.Nombre AS Area,
    s.SeccionId,
    s.Nombre AS Seccion,
    m.MaquinariaId,
    m.CodigoOrigen,
    m.Nombre AS Maquinaria,
    a.Activo AS AreaActiva,
    s.Activo AS SeccionActiva,
    m.Activo AS MaquinariaActiva
FROM dbo.Areas AS a
INNER JOIN dbo.Secciones AS s ON s.AreaId = a.AreaId
INNER JOIN dbo.Maquinarias AS m ON m.SeccionId = s.SeccionId;
GO

SELECT * FROM dbo.vw_AreaSeccionMaquinaria ORDER BY Area, Seccion, Maquinaria;
GO
"""
    output.write_text(sql, encoding="utf-8")
    print(f"Generado: {output} ({len(rows)} registros de maquinaria).")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
