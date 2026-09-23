#!/usr/bin/env bash
# Aktualisierung von {{NAME}} auf eine bestimmte Fassung.
#
#     deploy/update.sh 1.2.3
#
# Der Ablauf ist bewusst eng: erst sichern, dann den Kennsatz eintragen, dann
# das Abbild holen, wandern, starten, prüfen. Bricht ein Schritt ab, steht die
# Sicherung bereits — und der Rückweg ist derselbe Aufruf mit dem alten
# Kennsatz.

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

sicherung="$(ls -1t "/opt/backups/{{NAME}}"/*.dump 2>/dev/null | head -n 1 || true)"

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

meldung "Wanderungen ausführen"
docker compose run --rm -e CONTAINER_ROLE=worker app \
    php artisan migrate --force || rueckweg

meldung "Verbund starten"
docker compose up -d --wait || rueckweg

# Nach dem Start die Arbeiter auf den neuen Code holen; scheitert der Aufruf,
# weil die Fassung ihn noch nicht kennt, ist das kein Grund zum Abbruch.
docker compose exec -T app php artisan reload || true

# -------------------------------------------------------------------- Zustand
meldung "Zustand prüfen"
docker compose exec -T app curl -fsS http://127.0.0.1:8080/up >/dev/null || {
    echo "Der Zustandsbericht unter /up antwortet nicht." >&2
    rueckweg
}

laeuft="$(docker compose exec -T app php -r 'echo getenv("APP_IMAGE_VERSION");' | tr -d '[:space:]')"

if [ "$laeuft" != "$neu" ]; then
    echo "Es läuft Fassung '${laeuft}', erwartet war '${neu}'." >&2
    rueckweg
fi

meldung "Fertig — es läuft Fassung ${laeuft}"
if [ -n "$sicherung" ]; then
    echo "Sicherung dieses Laufs: ${sicherung}"
fi
echo "Rückweg, falls nötig: deploy/update.sh ${alt}"
