"""Zustandsbericht und Beispielmodul.

Der Zustandsbericht ist die Stelle, auf die der Compose-Healthcheck zeigt und
an der ohne Serverzugang abzulesen ist, welche Fassung läuft. Fällt er still
aus, merkt es niemand, bis er gebraucht wird.
"""

from fastapi.testclient import TestClient

from app.settings import get_settings


def test_zustandsbericht_antwortet_mit_fassung(client: TestClient) -> None:
    antwort = client.get("/healthz")

    assert antwort.status_code == 200
    assert antwort.json() == {"status": "ok", "version": get_settings().version}


def test_gruss_gibt_den_namen_zurueck(client: TestClient) -> None:
    antwort = client.get("/beispiel/gruss/Welt")

    assert antwort.status_code == 200
    assert antwort.json() == {"gruss": "Guten Tag, Welt!", "name": "Welt"}


def test_zu_langer_name_wird_abgewiesen(client: TestClient) -> None:
    antwort = client.get("/beispiel/gruss/" + "x" * 101)

    assert antwort.status_code == 422
