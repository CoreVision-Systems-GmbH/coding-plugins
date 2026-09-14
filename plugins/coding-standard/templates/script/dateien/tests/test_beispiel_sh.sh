#!/usr/bin/env bash
# Prüfungen für scripts/beispiel.sh — ohne fremdes Test-Rahmenwerk.
#
#     bash tests/test_beispiel_sh.sh
#
# Geprüft wird, was das Skript zusagt: --help beschreibt sich, --dry-run
# ändert nichts, der zweite Aufruf ändert nichts mehr (Idempotenz), eine
# unbekannte Option endet mit einem Ausgangswert ungleich 0.
#
# Bats wäre das naheliegende Rahmenwerk, ist unter Windows aber ein
# zusätzlicher Installationsschritt für vier Fälle. Sobald die Suite
# wächst, lohnt der Wechsel.

set -uo pipefail

hier="$(cd "$(dirname "$0")" && pwd)"
skript="$hier/../scripts/beispiel.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fehler=0

pruefe() { # <name> <erwarteter ausgangswert> <befehl...>
    local name="$1" erwartet="$2"
    shift 2
    local ausgabe status
    ausgabe="$("$@" 2>&1)"
    status=$?
    if [ "$status" -eq "$erwartet" ]; then
        echo "ok     $name"
    else
        echo "FEHLER $name (Ausgangswert $status, erwartet $erwartet)"
        printf '%s\n' "$ausgabe" | head -3 | sed 's/^/       | /'
        fehler=$((fehler + 1))
    fi
}

behaupte() { # <name> <bedingung erfüllt: 0/1>
    if [ "$2" -eq 0 ]; then
        echo "ok     $1"
    else
        echo "FEHLER $1"
        fehler=$((fehler + 1))
    fi
}

pruefe "--help endet sauber" 0 bash "$skript" --help
pruefe "unbekannte Option endet mit 1" 1 bash "$skript" --gibtesnicht

ziel="$tmp/probe"

bash "$skript" --ziel "$ziel" --dry-run >/dev/null 2>&1
if [ -d "$ziel" ]; then
    behaupte "--dry-run legt nichts an" 1
else
    behaupte "--dry-run legt nichts an" 0
fi

pruefe "erster Lauf legt an" 0 bash "$skript" --ziel "$ziel"
if [ -f "$ziel/.angelegt" ]; then
    behaupte "Markerdatei ist da" 0
else
    behaupte "Markerdatei ist da" 1
fi

inhalt_vorher="$(cat "$ziel/.angelegt")"
pruefe "zweiter Lauf endet sauber" 0 bash "$skript" --ziel "$ziel"
inhalt_nachher="$(cat "$ziel/.angelegt")"
if [ "$inhalt_vorher" = "$inhalt_nachher" ]; then
    behaupte "zweiter Lauf ändert nichts (idempotent)" 0
else
    behaupte "zweiter Lauf ändert nichts (idempotent)" 1
fi

echo
if [ "$fehler" -eq 0 ]; then
    echo "Alle Fälle grün."
else
    echo "Fehler: $fehler"
    exit 1
fi
