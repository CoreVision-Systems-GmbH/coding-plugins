#!/usr/bin/env bash
# Gerüst für den Stack fastapi.
#
# Wird von scripts/projekt-neu.sh zweimal aufgerufen:
#   PHASE=geruest     — Zielordner ist leer oder fehlt; hier wird nur angelegt.
#   PHASE=einrichten  — die Vorlagen liegen bereits im Zielordner.
#
# Es gibt keinen Installer: Das Gerüst kommt vollständig aus templates/fastapi/dateien.
# Diese Phase richtet die Umgebung ein und lässt einmal alle Prüfungen laufen —
# ein Gerüst, das nicht grün ist, wird gar nicht erst ausgeliefert.
#
# Umgebung: NAME DIR OWNER IMAGE PURPOSE ENV_PREFIX PHASE

set -euo pipefail

meldung() { printf '   %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

if [ "$PHASE" = "geruest" ]; then
    mkdir -p "$DIR"
    exit 0
fi

cd "$DIR"

command -v python >/dev/null 2>&1 || abbruch "python ist nicht im PATH."

meldung "Virtuelle Umgebung anlegen (.venv)"
python -m venv .venv

# Unter Windows liegen die Programme in .venv/Scripts, unter Linux in .venv/bin.
if [ -x .venv/Scripts/python.exe ]; then
    PY=".venv/Scripts/python.exe"
else
    PY=".venv/bin/python"
fi

meldung "Abhängigkeiten installieren"
"$PY" -m pip install --quiet --upgrade pip
"$PY" -m pip install --quiet -r requirements-dev.txt

meldung "ruff format --check ."
"$PY" -m ruff format --check .

meldung "ruff check ."
"$PY" -m ruff check .

meldung "mypy app"
"$PY" -m mypy app

meldung "pytest"
"$PY" -m pytest -q

meldung "Gerüst steht und ist grün."
