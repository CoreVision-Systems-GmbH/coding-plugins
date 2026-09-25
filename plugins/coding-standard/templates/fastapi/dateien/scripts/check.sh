#!/usr/bin/env bash
# check.sh — alle Prüfungen des Dienstes in einem Aufruf, dieselben wie in der CI.
#
# Aufruf:   bash scripts/check.sh [--help]
# Ändert:   nichts — liest nur und prüft.
# Rückweg:  keiner nötig.
#
# Reihenfolge: ruff format --check → ruff check → mypy app → pytest → Konfiguration →
# Lizenzen. Nimmt das Python der
# virtuellen Umgebung (.venv), sonst das aus dem PATH — so läuft derselbe Befehl in der CI.

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

cd "$(dirname "$0")/.."

if [ -x .venv/Scripts/python.exe ]; then
    PY=".venv/Scripts/python.exe"
elif [ -x .venv/bin/python ]; then
    PY=".venv/bin/python"
else
    PY="$(command -v python || command -v python3)" \
        || { echo "FEHLER: kein Python gefunden — .venv anlegen (python -m venv .venv) oder Python in den PATH." >&2; exit 1; }
fi

schritt() { printf '\n== %s\n' "$1"; }

schritt "ruff format --check ."
"$PY" -m ruff format --check .
schritt "ruff check ."
"$PY" -m ruff check .
schritt "mypy app"
"$PY" -m mypy app
schritt "pytest -q"
"$PY" -m pytest -q
schritt "komplexitaet-pruefen.sh (bis Ende 2026 Warnung)"
bash scripts/komplexitaet-pruefen.sh
schritt "konfig-pruefen.sh"
bash scripts/konfig-pruefen.sh
schritt "lizenzen-pruefen.sh"
bash scripts/lizenzen-pruefen.sh

printf '\nAlle Prüfungen grün.\n'
