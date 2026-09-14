#!/usr/bin/env bash
# Gerüst für den Stack script.
#
# Wird von scripts/projekt-neu.sh zweimal aufgerufen:
#   PHASE=geruest     — Zielordner ist leer oder fehlt; hier wird nur angelegt.
#   PHASE=einrichten  — die Vorlagen liegen bereits im Zielordner.
#
# Es gibt keinen Installer und keine Umgebung: Das Gerüst kommt vollständig aus
# templates/script/dateien. Diese Phase lässt die Beispiele einmal laufen —
# ein Gerüst, das nicht durchläuft, wird gar nicht erst ausgeliefert.
#
# Umgebung: NAME DIR OWNER IMAGE PURPOSE ENV_PREFIX PHASE

set -euo pipefail

meldung() { printf '   %s\n' "$1"; }

if [ "$PHASE" = "geruest" ]; then
    mkdir -p "$DIR"
    exit 0
fi

cd "$DIR"

chmod +x scripts/*.sh tests/*.sh 2>/dev/null || true

meldung "scripts/beispiel.sh --help"
bash scripts/beispiel.sh --help >/dev/null

meldung "tests/test_beispiel_sh.sh"
bash tests/test_beispiel_sh.sh

if command -v python >/dev/null 2>&1; then
    meldung "python scripts/beispiel.py --help"
    python scripts/beispiel.py --help >/dev/null
else
    meldung "python nicht gefunden — das Python-Beispiel wurde nicht ausprobiert"
fi

meldung "Gerüst steht."
