"""Gemeinsame Vorrichtungen der Testsuite."""

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

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
