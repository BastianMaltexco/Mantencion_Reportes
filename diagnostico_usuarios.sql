/* Ejecute este bloque en ReportesMantencion y comparta la grilla de resultados. */
USE [ReportesMantencion];
GO

SELECT
    c.column_id AS Orden,
    c.name AS Columna,
    t.name AS Tipo,
    c.max_length AS LargoMaximo,
    c.is_nullable AS AceptaNulo
FROM sys.columns AS c
INNER JOIN sys.types AS t ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID(N'dbo.Usuarios')
ORDER BY c.column_id;

SELECT
    kc.name AS Restriccion,
    kc.type_desc AS TipoRestriccion,
    c.name AS ColumnaClave
FROM sys.key_constraints AS kc
INNER JOIN sys.index_columns AS ic
    ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
INNER JOIN sys.columns AS c
    ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE kc.parent_object_id = OBJECT_ID(N'dbo.Usuarios');
