"""Fachlogik des Beispielmoduls.

Hier steht kein FastAPI-Import: Was der Service entscheidet, muss ohne HTTP
prüfbar sein. Der Router ruft ihn auf, ein Test ruft ihn direkt auf.
"""

from app.modules.beispiel.schemas import GrussAntwort


def gruessen(name: str) -> GrussAntwort:
    """Baut den Gruß.

    Der Name wird von Rändern befreit; ein leerer Name führt zu einer
    allgemeinen Anrede statt zu einem Fehler — die Entscheidung gehört hierher,
    nicht in den Router.
    """
    sauber = name.strip()

    if not sauber:
        return GrussAntwort(gruss="Guten Tag!", name="")

    return GrussAntwort(gruss=f"Guten Tag, {sauber}!", name=sauber)
