"""Aufbau der Anwendung: App-Objekt, Zustandsbericht, Router-Registrierung.

Hier steht keine Fachlogik. Was entschieden oder gerechnet wird, liegt in den
Services der Module unter ``app/modules/``.
"""

from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import PlainTextResponse

from app.modules.beispiel.router import router as beispiel_router
from app.schemas import Zustand
from app.settings import get_settings

SECURITY_TXT = Path(__file__).with_name("security.txt")

app = FastAPI(
    title="{{NAME}}",
    description="{{PURPOSE}}",
    version=get_settings().version,
)


@app.get("/healthz", response_model=Zustand, tags=["Betrieb"])
def healthz() -> Zustand:
    """Zustandsbericht ohne äußere Abhängigkeiten.

    Der Compose-Healthcheck zeigt hierher. Die Antwort darf deshalb weder die
    Datenbank noch einen fremden Dienst befragen — sonst meldet der Container
    sich als krank, obwohl er selbst arbeitet. Eine Prüfung mit Datenbank
    gehört unter ``/readyz``.
    """
    return Zustand(status="ok", version=get_settings().version)


@app.get(
    "/.well-known/security.txt",
    response_class=PlainTextResponse,
    include_in_schema=False,
)
def security_txt() -> str:
    """Kontakt für Sicherheitsmeldungen nach RFC 9116.

    Eine API hat keinen öffentlichen Ordner, deshalb liefert sie die Datei selbst
    aus. Gepflegt wird sie in ``app/security.txt`` — ``scripts/konfig-pruefen.sh``
    meldet, bevor ``Expires`` abläuft.
    """
    return SECURITY_TXT.read_text(encoding="utf-8")


app.include_router(beispiel_router)
