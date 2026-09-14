#!/usr/bin/env bash
# Sicherung der abgelegten Daten.
#
#     deploy/backup.sh
#
# Legt unter /opt/backups/{{NAME}} je Lauf ein Archiv des Datenbands ab
# (DATA_DIR im Container, Volume app_data). Ältere Stände als vierzehn Tage
# werden entfernt.
#
# Erfolgreich ist der Lauf nur, wenn das Archiv am Ende nicht leer ist — eine
# leere Sicherung ist schlimmer als keine, weil sie eine vortäuscht.
# deploy/update.sh bricht ab, wenn dieses Skript nicht sauber endet.
#
# Kommt eine PostgreSQL-Datenbank dazu, gehört `pg_dump -Fc` davor — nach
# demselben Muster: erst sichern, dann prüfen, dass die Datei nicht leer ist.

set -euo pipefail

cd "$(dirname "$0")/.."

ZIEL="/opt/backups/{{NAME}}"
AUFBEWAHRUNG_TAGE=14
VOLUME="{{NAME}}_app_data"

meldung() { printf '\n== %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

[ -f .env ] || abbruch "Die .env fehlt."

mkdir -p "$ZIEL"
stempel="$(date +%Y-%m-%d-%H%M%S)"
archiv="${ZIEL}/${stempel}-data.tar.gz"

meldung "Datenband sichern"
docker run --rm \
    -v "${VOLUME}:/data:ro" \
    -v "${ZIEL}:/backup" \
    alpine:3 tar -czf "/backup/${stempel}-data.tar.gz" -C /data . \
    || abbruch "Das Archiv des Datenbands ist gescheitert."

[ -s "$archiv" ] || abbruch "Das Archiv des Datenbands ist leer: $archiv"

meldung "Alte Stände entfernen (älter als ${AUFBEWAHRUNG_TAGE} Tage)"
find "$ZIEL" -maxdepth 1 -type f -name '*-data.tar.gz' \
    -mtime "+${AUFBEWAHRUNG_TAGE}" -print -delete

meldung "Sicherung fertig"
ls -lh "$archiv"
