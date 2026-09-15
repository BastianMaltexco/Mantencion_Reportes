"""Almacenamiento privado de adjuntos para web y API.

Las claves persistidas en SQL identifican objetos, nunca URLs públicas. El
proveedor se selecciona con FILE_STORAGE_BACKEND: local o azure_blob.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterator

from flask import current_app
from werkzeug.datastructures import FileStorage


class StorageError(RuntimeError):
    """Fallo de almacenamiento sin filtrar detalles o secretos del proveedor."""


@dataclass(frozen=True)
class StoredObject:
    key: str
    content_type: str
    size: int


class FileStorageBackend(ABC):
    """Contrato independiente del soporte físico de archivos."""

    @abstractmethod
    def save(self, key: str, file: FileStorage, content_type: str) -> StoredObject: ...

    @abstractmethod
    def exists(self, key: str) -> bool: ...

    @abstractmethod
    def read_bytes(self, key: str) -> bytes: ...

    @abstractmethod
    def iter_bytes(self, key: str, chunk_size: int = 64 * 1024) -> Iterator[bytes]: ...

    @abstractmethod
    def delete(self, key: str) -> None: ...


def safe_key(*parts: str) -> str:
    """Crea/valida claves POSIX sin rutas absolutas ni traversal."""
    key = PurePosixPath(*[str(part).replace("\\", "/") for part in parts]).as_posix()
    path = PurePosixPath(key)
    if path.is_absolute() or ".." in path.parts or key in {"", "."}:
        raise StorageError("Identificador de archivo inválido.")
    return key


def report_key(report_id: int, filename: str) -> str:
    return safe_key("reports", str(report_id), filename)


def fuel_key(load_id: int, filename: str) -> str:
    return safe_key("fuel-loads", str(load_id), filename)


def legacy_report_key(report_id: int, stored_name: str) -> str:
    # Azure usa el prefijo lógico para identificadores previos sin ruta.
    return safe_key(stored_name) if "/" in stored_name or "\\" in stored_name else report_key(report_id, stored_name)


def legacy_fuel_key(load_id: int, stored_name: str) -> str:
    return safe_key(stored_name) if "/" in stored_name or "\\" in stored_name else fuel_key(load_id, stored_name)


def local_legacy_report_key(report_id: int, stored_name: str) -> str:
    """Ruta usada por la aplicación antes de introducir esta abstracción."""
    return safe_key(stored_name) if "/" in stored_name or "\\" in stored_name else safe_key(str(report_id), stored_name)


def local_legacy_fuel_key(load_id: int, stored_name: str) -> str:
    return safe_key(stored_name) if "/" in stored_name or "\\" in stored_name else safe_key("fuel", str(load_id), stored_name)


def resolve_report_key(storage: FileStorageBackend, report_id: int, stored_name: str) -> str:
    return local_legacy_report_key(report_id, stored_name) if isinstance(storage, LocalFileStorage) else legacy_report_key(report_id, stored_name)


def resolve_fuel_key(storage: FileStorageBackend, load_id: int, stored_name: str) -> str:
    return local_legacy_fuel_key(load_id, stored_name) if isinstance(storage, LocalFileStorage) else legacy_fuel_key(load_id, stored_name)


class LocalFileStorage(FileStorageBackend):
    """Proveedor para desarrollo y compatibilidad con uploads existentes."""

    def __init__(self, root: str | Path):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        key = safe_key(key)
        path = (self.root / key).resolve()
        if self.root != path and self.root not in path.parents:
            raise StorageError("Identificador de archivo inválido.")
        return path

    def save(self, key: str, file: FileStorage, content_type: str) -> StoredObject:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            raise StorageError("Ya existe un archivo con ese identificador.")
        try:
            file.save(path)
        except OSError as error:
            raise StorageError("No fue posible guardar el archivo.") from error
        return StoredObject(key=key, content_type=content_type, size=path.stat().st_size)

    def exists(self, key: str) -> bool:
        return self._path(key).is_file()

    def read_bytes(self, key: str) -> bytes:
        path = self._path(key)
        try:
            return path.read_bytes()
        except FileNotFoundError:
            raise
        except OSError as error:
            raise StorageError("No fue posible recuperar el archivo.") from error

    def iter_bytes(self, key: str, chunk_size: int = 64 * 1024) -> Iterator[bytes]:
        path = self._path(key)
        try:
            with path.open("rb") as stream:
                while chunk := stream.read(chunk_size):
                    yield chunk
        except FileNotFoundError:
            raise
        except OSError as error:
            raise StorageError("No fue posible recuperar el archivo.") from error

    def delete(self, key: str) -> None:
        try:
            self._path(key).unlink(missing_ok=True)
        except OSError as error:
            raise StorageError("No fue posible eliminar el archivo.") from error


class AzureBlobStorage(FileStorageBackend):
    """Proveedor privado; solo Flask conoce la cadena de conexión."""

    def __init__(self, connection_string: str, container: str):
        if not connection_string or not container:
            raise StorageError("Falta configuración de Azure Blob Storage.")
        try:
            from azure.storage.blob import BlobServiceClient
        except ImportError as error:
            raise StorageError("Falta la dependencia azure-storage-blob.") from error
        self._container_name = container
        self._container_client = BlobServiceClient.from_connection_string(connection_string).get_container_client(container)

    def save(self, key: str, file: FileStorage, content_type: str) -> StoredObject:
        from azure.core.exceptions import AzureError
        from azure.storage.blob import ContentSettings

        key = safe_key(key)
        try:
            file.stream.seek(0)
            self._container_client.get_blob_client(key).upload_blob(
                file.stream, overwrite=False, content_settings=ContentSettings(content_type=content_type)
            )
            size = file.content_length or _stream_size(file)
            return StoredObject(key=key, content_type=content_type, size=size)
        except AzureError as error:
            raise StorageError("No fue posible guardar el archivo en Azure Blob Storage.") from error

    def exists(self, key: str) -> bool:
        from azure.core.exceptions import AzureError, ResourceNotFoundError

        try:
            return self._container_client.get_blob_client(safe_key(key)).exists()
        except ResourceNotFoundError:
            return False
        except AzureError as error:
            raise StorageError("No fue posible consultar el archivo en Azure Blob Storage.") from error

    def read_bytes(self, key: str) -> bytes:
        from azure.core.exceptions import AzureError, ResourceNotFoundError

        try:
            return self._container_client.download_blob(safe_key(key)).readall()
        except ResourceNotFoundError as error:
            raise FileNotFoundError(key) from error
        except AzureError as error:
            raise StorageError("No fue posible recuperar el archivo desde Azure Blob Storage.") from error

    def iter_bytes(self, key: str, chunk_size: int = 64 * 1024) -> Iterator[bytes]:
        from azure.core.exceptions import AzureError, ResourceNotFoundError

        try:
            downloader = self._container_client.download_blob(safe_key(key), max_concurrency=1)
            yield from downloader.chunks()
        except ResourceNotFoundError as error:
            raise FileNotFoundError(key) from error
        except AzureError as error:
            raise StorageError("No fue posible recuperar el archivo desde Azure Blob Storage.") from error

    def delete(self, key: str) -> None:
        from azure.core.exceptions import AzureError, ResourceNotFoundError

        try:
            self._container_client.delete_blob(safe_key(key))
        except ResourceNotFoundError:
            return
        except AzureError as error:
            raise StorageError("No fue posible eliminar el archivo de Azure Blob Storage.") from error


def _stream_size(file: FileStorage) -> int:
    stream = file.stream
    position = stream.tell()
    stream.seek(0, 2)
    size = stream.tell()
    stream.seek(position)
    return size


def get_file_storage() -> FileStorageBackend:
    """Obtiene una instancia por aplicación para reutilizar conexiones Azure."""
    storage = current_app.extensions.get("file_storage")
    if storage:
        return storage
    backend = current_app.config.get("FILE_STORAGE_BACKEND", "local").lower()
    if backend == "local":
        storage = LocalFileStorage(current_app.config["UPLOAD_FOLDER"])
    elif backend == "azure_blob":
        storage = AzureBlobStorage(
            current_app.config.get("AZURE_STORAGE_CONNECTION_STRING", ""),
            current_app.config["AZURE_STORAGE_CONTAINER"],
        )
    else:
        raise StorageError("FILE_STORAGE_BACKEND debe ser local o azure_blob.")
    current_app.extensions["file_storage"] = storage
    return storage
