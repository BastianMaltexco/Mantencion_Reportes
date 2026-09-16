/*
   Aplica los cinco tipos para registros NUEVOS sin alterar ni borrar valores
   históricos. WITH NOCHECK permite conservar filas existentes con los tipos
   antiguos; el CHECK se aplica a INSERT/UPDATE posteriores.
*/
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.Reportes')
      AND name = N'CK_Reportes_TipoServicio'
)
    ALTER TABLE dbo.Reportes DROP CONSTRAINT CK_Reportes_TipoServicio;

ALTER TABLE dbo.Reportes WITH NOCHECK
ADD CONSTRAINT CK_Reportes_TipoServicio
CHECK (TipoServicio IN (N'Correctiva', N'Preventiva', N'Predictiva', N'Nueva instalación', N'Otro'));

COMMIT TRANSACTION;
