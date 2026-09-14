"""HTTP-Endpunkte des Beispielmoduls.

Der Router bleibt dünn: parsen, autorisieren, an den Service delegieren, das
Antwort-Schema zurückgeben. Sobald hier eine Bedingung steht, die etwas
fachlich entscheidet, gehört sie in den Service.

Autorisierung käme als Abhängigkeit dazu — entweder am Router
(``APIRouter(dependencies=[Depends(...)])``) oder an der einzelnen Route. Nie
im Client, nie in einer Vorlage.
"""

from fastapi import APIRouter, Path

from app.modules.beispiel.schemas import GrussAntwort
from app.modules.beispiel.service import gruessen

router = APIRouter(prefix="/beispiel", tags=["Beispiel"])


@router.get("/gruss/{name}", response_model=GrussAntwort)
def gruss(name: str = Path(max_length=100, description="Wer gegrüßt wird.")) -> GrussAntwort:
    """Grüßt den übergebenen Namen."""
    return gruessen(name)
