"""Kontakt für Sicherheitsmeldungen (RFC 9116, Cyber Resilience Act).

Wer eine Schwachstelle findet, sucht den Kontakt unter ``/.well-known/security.txt``.
Fehlt die Datei oder ist sie abgelaufen, geht die Meldung ins Leere — oder an ein
öffentliches Issue.
"""

from datetime import UTC, datetime

from fastapi.testclient import TestClient


def test_security_txt_nennt_kontakt_und_gueltiges_ablaufdatum(client: TestClient) -> None:
    antwort = client.get("/.well-known/security.txt")

    assert antwort.status_code == 200
    assert antwort.headers["content-type"].startswith("text/plain")
    felder = dict(
        zeile.split(": ", 1)
        for zeile in antwort.text.splitlines()
        if zeile and not zeile.startswith("#")
    )
    assert felder["Contact"].startswith("mailto:")
    ablauf = datetime.fromisoformat(felder["Expires"].replace("Z", "+00:00"))
    assert ablauf > datetime.now(UTC)
