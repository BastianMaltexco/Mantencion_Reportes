"""Migración segura, de una vía, desde SQL Server local a Azure SQL Database.

Por defecto solo audita. Use --apply únicamente cuando el informe no indique
incompatibilidades. Nunca ejecuta sentencias de escritura contra el origen.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from dotenv import dotenv_values
from sqlalchemy import MetaData, create_engine, inspect, select, text
from sqlalchemy.engine import URL


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ENV = PROJECT_ROOT / ".env"
TARGET_ENV = PROJECT_ROOT / ".env.azure-test"
SCHEMA = "dbo"


def engine_from_env(path: Path, *, azure: bool):
    values = dotenv_values(path)
    required = ("DB_SERVER", "DB_NAME", "DB_USER", "DB_PASSWORD")
    missing = [key for key in required if not values.get(key)]
    if missing:
        raise RuntimeError(f"Faltan {', '.join(missing)} en {path.name}.")

    return create_engine(
        URL.create(
            "mssql+pyodbc",
            username=values["DB_USER"],
            password=values["DB_PASSWORD"],
            host=values["DB_SERVER"],
            port=int(values.get("DB_PORT") or 1433),
            database=values["DB_NAME"],
            query={
                "driver": values.get("DB_DRIVER") or "ODBC Driver 18 for SQL Server",
                "Encrypt": values.get("DB_ENCRYPT") or ("yes" if azure else "no"),
                "TrustServerCertificate": values.get("DB_TRUST_SERVER_CERTIFICATE")
                or ("no" if azure else "yes"),
            },
            ),
        future=True,
    )


def source_audit(connection):
    """Devuelve objetos que requieren una migración manual o no son compatibles."""
    unsupported = connection.execute(
        text(
            """
            SELECT s.name AS schema_name, o.name, o.type_desc
            FROM sys.objects AS o
            INNER JOIN sys.schemas AS s ON s.schema_id = o.schema_id
            WHERE o.is_ms_shipped = 0
              AND o.type IN ('P', 'PC', 'TR', 'FN', 'IF', 'TF', 'AF', 'FS', 'FT', 'SO', 'SN')
            ORDER BY o.type_desc, s.name, o.name
            """
        )
    ).all()
    advanced_columns = connection.execute(
        text(
            """
            SELECT s.name AS schema_name, t.name AS table_name, c.name AS column_name,
                   c.is_computed, c.generated_always_type
            FROM sys.columns AS c
            INNER JOIN sys.tables AS t ON t.object_id = c.object_id
            INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
            WHERE t.is_ms_shipped = 0
              AND (c.is_computed = 1 OR c.generated_always_type <> 0)
            ORDER BY s.name, t.name, c.column_id
            """
        )
    ).all()
    cross_database = connection.execute(
        text(
            """
            SELECT DISTINCT referenced_database_name
            FROM sys.sql_expression_dependencies
            WHERE referenced_database_name IS NOT NULL
            """
        )
    ).all()
    return unsupported, advanced_columns, cross_database


def view_definitions(connection):
    rows = connection.execute(
        text(
            """
            SELECT s.name AS schema_name, v.name, OBJECT_DEFINITION(v.object_id) AS definition
            FROM sys.views AS v
            INNER JOIN sys.schemas AS s ON s.schema_id = v.schema_id
            WHERE v.is_ms_shipped = 0
            ORDER BY s.name, v.name
            """
        )
    ).mappings()
    return list(rows)


def check_definitions(connection):
    rows = connection.execute(
        text(
            """
            SELECT s.name AS schema_name, t.name AS table_name, cc.name, cc.definition
            FROM sys.check_constraints AS cc
            INNER JOIN sys.tables AS t ON t.object_id = cc.parent_object_id
            INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
            WHERE t.is_ms_shipped = 0
            ORDER BY s.name, t.name, cc.name
            """
        )
    ).mappings()
    return list(rows)


def quote_identifier(identifier: str):
    return "[" + identifier.replace("]", "]]" ) + "]"


def add_check_constraints(target_engine, checks):
    """SQLAlchemy refleja índices/FK correctamente, pero no todos los CHECK de SQL Server."""
    with target_engine.begin() as target:
        existing = {
            row.name
            for row in target.execute(
                text("SELECT name FROM sys.check_constraints")
            ).mappings()
        }
        for check in checks:
            if check["name"] in existing:
                continue
            table_name = f"{quote_identifier(check['schema_name'])}.{quote_identifier(check['table_name'])}"
            constraint_name = quote_identifier(check["name"])
            target.exec_driver_sql(
                f"ALTER TABLE {table_name} WITH CHECK ADD CONSTRAINT {constraint_name} CHECK {check['definition']}"
            )
            target.exec_driver_sql(f"ALTER TABLE {table_name} CHECK CONSTRAINT {constraint_name}")
            print(f"Agregada restricción CHECK {check['name']}")


def table_counts(connection, table_names):
    return {
        table.name: connection.execute(select(text("COUNT(*)")).select_from(table)).scalar_one()
        for table in table_names
    }


def quoted_name(connection, table):
    preparer = connection.dialect.identifier_preparer
    return f"{preparer.quote_schema(table.schema)}.{preparer.quote(table.name)}"


def copy_table(source, target, table, batch_size=500):
    """Copia filas preservando claves identity, sin tocar nunca el origen."""
    has_identity = any(column.identity is not None for column in table.columns)
    source_result = source.execute(select(table))
    copied = 0
    with target.begin() as destination:
        qualified = quoted_name(destination, table)
        if has_identity:
            destination.exec_driver_sql(f"SET IDENTITY_INSERT {qualified} ON")
        try:
            while True:
                rows = source_result.mappings().fetchmany(batch_size)
                if not rows:
                    break
                destination.execute(table.insert(), [dict(row) for row in rows])
                copied += len(rows)
        finally:
            if has_identity:
                destination.exec_driver_sql(f"SET IDENTITY_INSERT {qualified} OFF")
    return copied


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Crea esquema y copia datos al destino vacío.")
    args = parser.parse_args()

    source_engine = engine_from_env(SOURCE_ENV, azure=False)
    target_engine = engine_from_env(TARGET_ENV, azure=True)
    try:
        with source_engine.connect() as source, target_engine.connect() as target:
            source_name = source.execute(text("SELECT DB_NAME()")).scalar_one()
            target_name = target.execute(text("SELECT DB_NAME()")).scalar_one()
            print(f"Origen conectado: {source_name}")
            print(f"Destino conectado: {target_name}")
            unsupported, advanced_columns, cross_database = source_audit(source)
            if unsupported or advanced_columns or cross_database:
                print("MIGRACION BLOQUEADA: se requiere revisión manual.")
                for item in unsupported:
                    print(f"Objeto no migrable automáticamente: {item.schema_name}.{item.name} ({item.type_desc})")
                for item in advanced_columns:
                    print(f"Columna avanzada: {item.schema_name}.{item.table_name}.{item.column_name}")
                for item in cross_database:
                    print(f"Dependencia entre bases: {item.referenced_database_name}")
                raise SystemExit(2)

            metadata = MetaData(schema=SCHEMA)
            metadata.reflect(bind=source, schema=SCHEMA, views=False)
            tables = list(metadata.sorted_tables)
            views = view_definitions(source)
            checks = check_definitions(source)
            existing_tables = inspect(target).get_table_names(schema=SCHEMA)
            print("Tablas de origen: " + ", ".join(table.name for table in tables))
            print("Vistas de origen: " + ", ".join(view["name"] for view in views))
            print("Conteos de origen: " + str(table_counts(source, tables)))
            if existing_tables:
                raise RuntimeError(
                    "El destino no está vacío; se cancela para evitar sobrescribir datos: "
                    + ", ".join(existing_tables)
                )
            if not args.apply:
                print("AUDITORIA OK. Ejecute con --apply para migrar al destino vacío.")
                return

        # Solo desde aquí se escribe en Azure SQL; el origen ya no se modifica.
        metadata.create_all(target_engine, checkfirst=False)
        with source_engine.connect() as source:
            for table in tables:
                copied = copy_table(source, target_engine, table)
                print(f"Copiada {table.name}: {copied} fila(s)")

        add_check_constraints(target_engine, checks)

        with target_engine.begin() as target:
            for view in views:
                target.exec_driver_sql(view["definition"])
                print(f"Creada vista {view['schema_name']}.{view['name']}")

        with source_engine.connect() as source, target_engine.connect() as target:
            source_counts = table_counts(source, tables)
            target_counts = table_counts(target, tables)
        print("CONTEOS_ORIGEN=" + str(source_counts))
        print("CONTEOS_DESTINO=" + str(target_counts))
        if source_counts != target_counts:
            raise RuntimeError("Los conteos no coinciden; revise el destino antes de usarlo.")
        print("MIGRACION COMPLETADA Y VERIFICADA")
    finally:
        source_engine.dispose()
        target_engine.dispose()


if __name__ == "__main__":
    main()
