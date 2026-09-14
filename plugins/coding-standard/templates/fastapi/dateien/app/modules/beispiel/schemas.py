"""Ein- und Ausgabe des Beispielmoduls.

Alles, was den Dienst verlässt, ist ein Pydantic-Modell — nie ein rohes Dict und
nie ein ORM-Objekt. Sonst wandert früher oder später ein Feld nach draußen, das
niemand dort haben wollte.
"""

from pydantic import BaseModel, Field


class GrussAntwort(BaseModel):
    """Antwort auf eine Begrüßung."""

    gruss: str = Field(description="Der ausformulierte Gruß.")
    name: str = Field(description="Der Name, wie er verstanden wurde.")
