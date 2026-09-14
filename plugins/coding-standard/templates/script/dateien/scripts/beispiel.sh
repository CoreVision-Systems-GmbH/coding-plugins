#!/usr/bin/env bash
# Beispielwerkzeug — Vorlage für ein echtes Skript.
#
# Es legt ein Verzeichnis samt Markerdatei an. Der Zweck ist nicht die Aufgabe,
# sondern die Form: --help, --dry-run, idempotent, Meldungen nach stderr,
# Ergebnis nach stdout, Ausgangswert ungleich 0 bei Fehlern.
#
# Aufruf:      scripts/beispiel.sh [--ziel <pfad>] [--dry-run] [--help]
# Ändert:     legt <ziel> an, schreibt <ziel>/.angelegt
# Ändert NIE: vorhandene Dateien in <ziel>
# Rückweg:    rm -rf <ziel>

set -euo pipefail

ZIEL="${TMPDIR:-/tmp}/{{NAME}}-beispiel"
TROCKEN=0

# Meldungen gehen nach stderr, damit stdout in einer Pipe brauchbar bleibt.
meldung() { printf '%s\n' "$*" >&2; }
abbruch() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }

hilfe() {
    cat <<'EOF'
Beispielwerkzeug von {{NAME}}.

Aufruf:
    scripts/beispiel.sh [Optionen]

Optionen:
    --ziel <pfad>   Zielverzeichnis (Vorgabe: $TMPDIR/{{NAME}}-beispiel)
    --dry-run       Nur zeigen, was passieren würde. Nichts ändern.
    --version       Fassung aus version.txt ausgeben.
    --help          Diese Hilfe.

Wirkung:
    Legt das Zielverzeichnis an und schreibt darin die Markerdatei .angelegt.
    Ein zweiter Aufruf ändert nichts mehr.

Rückweg:
    rm -rf <ziel>
EOF
}

fassung() {
    local datei
    datei="$(dirname "$0")/../version.txt"
    if [ -f "$datei" ]; then
        tr -d '\r\n' < "$datei"
        printf '\n'
    else
        printf 'unbekannt\n'
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --ziel)
            [ $# -ge 2 ] || abbruch "--ziel braucht einen Pfad."
            ZIEL="$2"
            shift 2
            ;;
        --dry-run)
            TROCKEN=1
            shift
            ;;
        --version)
            fassung
            exit 0
            ;;
        --help | -h)
            hilfe
            exit 0
            ;;
        *)
            abbruch "Unbekannte Option: $1 (siehe --help)"
            ;;
    esac
done

marker="${ZIEL}/.angelegt"

# Idempotenz: Was schon steht, wird nicht noch einmal angelegt.
if [ -f "$marker" ]; then
    meldung "Bereits angelegt: ${ZIEL}"
    printf '%s\n' "$ZIEL"
    exit 0
fi

if [ "$TROCKEN" -eq 1 ]; then
    meldung "Würde anlegen: ${ZIEL} (und darin .angelegt)"
    printf '%s\n' "$ZIEL"
    exit 0
fi

mkdir -p "$ZIEL"
printf 'angelegt am %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$marker"

meldung "Angelegt: ${ZIEL}"
printf '%s\n' "$ZIEL"
