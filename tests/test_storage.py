import io
import os
import uuid

import pytest
from werkzeug.datastructures import FileStorage

from app.services.storage import AzureBlobStorage, LocalFileStorage, local_legacy_report_key, report_key, resolve_report_key


def upload(data=b"storage-test", filename="test.png", mime_type="image/png"):
    return FileStorage(stream=io.BytesIO(data), filename=filename, content_type=mime_type)


def test_local_file_storage_round_trip_and_delete(tmp_path):
    storage = LocalFileStorage(tmp_path)
    key = report_key(42, "a" * 32 + ".png")
    stored = storage.save(key, upload(), "image/png")

    assert stored.key == key
    assert stored.size == len(b"storage-test")
    assert storage.exists(key)
    assert storage.read_bytes(key) == b"storage-test"
    assert b"".join(storage.iter_bytes(key, chunk_size=3)) == b"storage-test"
    storage.delete(key)
    assert not storage.exists(key)


def test_local_file_storage_resolves_existing_legacy_report_layout(tmp_path):
    storage = LocalFileStorage(tmp_path)
    legacy_key = local_legacy_report_key(9, "archivo-antiguo.png")
    path = tmp_path / legacy_key
    path.parent.mkdir(parents=True)
    path.write_bytes(b"legacy-local-file")

    assert resolve_report_key(storage, 9, "archivo-antiguo.png") == legacy_key
    assert storage.read_bytes(legacy_key) == b"legacy-local-file"


@pytest.mark.skipif(not os.environ.get("AZURE_STORAGE_CONNECTION_STRING"), reason="requiere secreto Azure temporal en el entorno")
def test_azure_blob_storage_round_trip_and_delete():
    """Prueba real: siempre elimina solamente el blob único generado aquí."""
    storage = AzureBlobStorage(os.environ["AZURE_STORAGE_CONNECTION_STRING"], os.environ.get("AZURE_STORAGE_CONTAINER", "reportes-adjuntos"))
    key = f"_tests/{uuid.uuid4().hex}.txt"
    try:
        stored = storage.save(key, upload(b"azure-storage-test", "test.txt", "text/plain"), "text/plain")
        assert stored.key == key
        assert storage.exists(key)
        assert storage.read_bytes(key) == b"azure-storage-test"
        assert b"".join(storage.iter_bytes(key)) == b"azure-storage-test"
    finally:
        storage.delete(key)
    assert not storage.exists(key)
