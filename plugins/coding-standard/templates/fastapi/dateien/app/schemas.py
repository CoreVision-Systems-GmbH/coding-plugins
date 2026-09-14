"""Schemas, die zu keinem Fachmodul gehören."""

from pydantic import BaseModel


class Zustand(BaseModel):
    """Antwort des Zustandsberichts unter ``/healthz``."""

    status: str
    version: str
