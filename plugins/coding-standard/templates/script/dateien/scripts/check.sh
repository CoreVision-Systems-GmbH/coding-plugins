#!/usr/bin/env bash
# check.sh — alle Prüfungen des Repos in einem Aufruf, dieselben wie in der CI.
#
# Aufruf:   bash scripts/check.sh [--help]
# Ändert:   nichts — liest nur und prüft.
# Rückweg:  keiner nötig.
#
# Prüft, was es im Repo gibt — getrackte und neue, noch nicht gestagte Dateien: shellcheck und
# die Shell-Tests tests/test_*.sh für *.sh, ruff und pytest für *.py. Fehlt ein Werkzeug, endet
# der Lauf rot mit dem Installationshinweis — ein stilles Grün ohne Prüfung gibt es nicht,
# auch nicht außerhalb eines Git-Repos. PowerShell-Skripte prüft die CI (PSScriptAnalyzer).

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

cd "$(dirname "$0")/.."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "FEHLER: kein Git-Repo — check.sh prüft die Dateien des Repos; in einem losen Ordner gäbe es ein stilles Grün." >&2; exit 1; }

# Getrackte und neue Dateien, ohne die aus .gitignore — der Befehl läuft vor dem Commit,
# also genau dann, wenn Neues noch nicht im Index ist.
dateien() { git ls-files --cached --others --exclude-standard -- "$@"; }

fehler=0
schritt() { printf '\n== %s\n' "$1"; }
fehlt() { printf 'FEHLER: %s fehlt — %s\n' "$1" "$2" >&2; fehler=1; }

mapfile -t shells < <(dateien '*.sh')
if [ ${#shells[@]} -gt 0 ]; then
    schritt "shellcheck (${#shells[@]} Dateien)"
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "${shells[@]}"
    else
        fehlt "shellcheck" "installieren mit: pip install shellcheck-py (oder apt install shellcheck)"
    fi
fi

# Shell-Tests liegen als tests/test_*.sh neben den Werkzeugen und laufen mit bash.
mapfile -t shelltests < <(dateien 'tests/test_*.sh')
for t in ${shelltests[@]+"${shelltests[@]}"}; do
    schritt "bash $t"
    bash "$t"
done

mapfile -t pys < <(dateien '*.py')
if [ ${#pys[@]} -gt 0 ]; then
    py="$(command -v python || command -v python3 || true)"
    schritt "ruff format --check . / ruff check ."
    if [ -n "$py" ] && "$py" -m ruff --version >/dev/null 2>&1; then
        "$py" -m ruff format --check .
        "$py" -m ruff check .
    else
        fehlt "ruff" "installieren mit: pip install ruff pytest"
    fi
    if [ -d tests ]; then
        schritt "pytest -q"
        if [ -n "$py" ] && "$py" -m pytest --version >/dev/null 2>&1; then
            "$py" -m pytest -q
        else
            fehlt "pytest" "installieren mit: pip install ruff pytest"
        fi
    fi
fi

schritt "komplexitaet-pruefen.sh (bis Ende 2026 Warnung)"
bash scripts/komplexitaet-pruefen.sh

if [ -n "$(dateien '*.ps1')" ]; then
    printf '\nHinweis: PowerShell-Skripte prüft die CI mit PSScriptAnalyzer — hier nicht geprüft.\n'
fi

# Diese Zeile erreicht nur ein Lauf, in dem alles Laufbare grün war und nur Werkzeuge fehlten —
# ein echter Befund bricht oben ab (set -e). Tests stützen sich auf genau diese Unterscheidung.
if [ "$fehler" -ne 0 ]; then
    printf '\nRot: nicht alle Prüfungen konnten laufen — fehlende Werkzeuge siehe oben.\n' >&2
    exit 1
fi
printf '\nAlle Prüfungen grün.\n'
