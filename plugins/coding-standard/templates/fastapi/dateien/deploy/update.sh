#!/usr/bin/env bash
# Aktualisierung von {{NAME}} auf eine bestimmte Fassung.
#
#     deploy/update.sh 1.2.3
#
# Der Ablauf ist bewusst eng: erst sichern, dann den Kennsatz eintragen, dann
# das Abbild holen, starten, prüfen. Bricht ein Schritt ab, steht die
# Sicherung bereits — und der Rückweg ist derselbe Aufruf mit dem alten
# Kennsatz.
#
# Sobald der Dienst Schemaänderungen kennt, gehört der Migrationsaufruf
# zwischen "Abbild laden" und "Verbund starten" — additiv, mit der Sicherung
# davor.

set -euo pipefail

cd "$(dirname "$0")/.."

meldung() { printf '\n== %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

if [ $# -ne 1 ]; then
    echo "Aufruf: deploy/update.sh <fassung>   (z. B. 1.2.3 oder v1.2.3)" >&2
    exit 1
fi

neu="${1#v}"

[ -f .env ] || abbruch "Die .env fehlt."

alt="$(sed -n 's/^APP_VERSION=//p' .env | head -n 1 | tr -d '\r')"
[ -n "$alt" ] || abbruch "In der .env steht kein APP_VERSION — Rückweg wäre unbekannt."

echo "Bisher: ${alt}    Neu: ${neu}"

# ------------------------------------------------------------------ Sicherung
meldung "Sicherung vor der Aktualisierung"
if ! deploy/backup.sh; then
    abbruch "Die Sicherung ist gescheitert. Ohne Sicherung wird nicht aktualisiert."
fi

sicherung="$(ls -1t "/opt/backups/{{NAME}}"/*.tar.gz 2>/dev/null | head -n 1 || true)"

rueckweg() {
    printf '\nRückweg: deploy/update.sh %s\n' "$alt" >&2
    if [ -n "$sicherung" ]; then
        printf 'Sicherung: %s\n' "$sicherung" >&2
    fi
    exit 1
}

# --------------------------------------------------------------- Neue Fassung
meldung "Kennsatz in der .env eintragen"
sed -i "s|^APP_VERSION=.*|APP_VERSION=${neu}|" .env

set -a
# shellcheck disable=SC1091
source .env
set +a

meldung "Abbild laden (Fassung ${neu})"
docker compose pull || rueckweg

meldung "Verbund starten"
docker compose up -d --wait || rueckweg

# -------------------------------------------------------------------- Zustand
meldung "Zustand prüfen"
antwort="$(docker compose exec -T app curl -fsS http://127.0.0.1:8080/healthz || true)"

if [ -z "$antwort" ]; then
    echo "Der Zustandsbericht unter /healthz antwortet nicht." >&2
    rueckweg
fi

case "$antwort" in
    *"\"version\":\"${neu}\""*) ;;
    *)
        echo "Der Zustandsbericht meldet nicht Fassung '${neu}': ${antwort}" >&2
        rueckweg
        ;;
esac

meldung "Fertig — es läuft Fassung ${neu}"
if [ -n "$sicherung" ]; then
    echo "Sicherung dieses Laufs: ${sicherung}"
fi
echo "Rückweg, falls nötig: deploy/update.sh ${alt}"
