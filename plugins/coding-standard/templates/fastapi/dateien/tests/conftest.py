"""Gemeinsame Vorrichtungen der Testsuite."""

import os
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

# Die Testsuite spricht nie mit der Datenbank aus der .env: Die Werte stehen fest
# verdrahtet, bevor die App ihre Konfiguration liest — Umgebung und .env des
# Rechners schlagen nicht durch. test.invalid löst nie auf. Der Import der App
# steht deshalb erst darunter.
os.environ.update(
    {
        "DB_HOST": "test.invalid",
        "DB_PORT": "5432",
        "DB_DATABASE": "test",
        "DB_USERNAME": "test",
        "DB_PASSWORD": "nur-fuer-tests",
    }
)

from app.main import app


@pytest.fixture
def client() -> Iterator[TestClient]:
    """Ein Client, der die Lebenszyklus-Ereignisse der App ausführt.

    ``TestClient(app)`` ohne ``with`` startet weder ``startup`` noch
    ``shutdown``. Wer sich darauf verlässt, testet eine App, die es im Betrieb
    so nicht gibt.
    """
    with TestClient(app) as c:
        yield c
