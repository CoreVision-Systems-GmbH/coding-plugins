"""Aufbau der Anwendung: App-Objekt, Zustandsbericht, Router-Registrierung.

Hier steht keine Fachlogik. Was entschieden oder gerechnet wird, liegt in den
Services der Module unter ``app/modules/``.
"""

from fastapi import FastAPI

from app.modules.beispiel.router import router as beispiel_router
from app.schemas import Zustand
from app.settings import get_settings

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


app.include_router(beispiel_router)
