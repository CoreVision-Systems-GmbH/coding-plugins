#!/usr/bin/env bash
# Aktualisierung von {{NAME}} auf eine bestimmte Fassung.
#
#     deploy/update.sh 1.2.3
#
# Der Ablauf ist bewusst eng: Abbild holen, Kennsatz eintragen, starten,
# prüfen. Eine Sicherung gibt es nicht — die Site hat keine Daten, kein
# Volume und keine Datenbank; alles, was läuft, steckt im Abbild und liegt
# als Tag in GHCR. Bricht ein Schritt ab, ist der Rückweg derselbe Aufruf mit
# dem alten Kennsatz.

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

rueckweg() {
    printf '\nRückweg: deploy/update.sh %s\n' "$alt" >&2
    exit 1
}

# --------------------------------------------------------------- Neue Fassung
meldung "Abbild laden (Fassung ${neu})"
# Erst holen, dann eintragen: Scheitert der Pull, nennt die .env weiterhin die
# Fassung, die tatsächlich läuft.
APP_VERSION="${neu}" docker compose pull || rueckweg

meldung "Kennsatz in der .env eintragen"
sed -i "s|^APP_VERSION=.*|APP_VERSION=${neu}|" .env

set -a
# shellcheck disable=SC1091
source .env
set +a

meldung "Verbund starten"
docker compose up -d --wait || rueckweg

# -------------------------------------------------------------------- Zustand
meldung "Zustand prüfen"
# wget aus BusyBox — curl gibt es im caddy-Abbild nicht.
antwort="$(docker compose exec -T app wget -qO- http://127.0.0.1:8080/healthz || true)"

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

# Rauchtest: die Routen aus deploy/smoke.txt mit Status, Zeitbudget und Pflichtinhalt.
# Rot heißt: Die neue Fassung läuft, aber nicht richtig — Rückweg wie bei jedem Fehler.
meldung "Rauchtest (deploy/smoke.txt)"
deploy/smoke.sh || rueckweg

meldung "Fertig — es läuft Fassung ${neu}"
echo "Rückweg, falls nötig: deploy/update.sh ${alt}"
