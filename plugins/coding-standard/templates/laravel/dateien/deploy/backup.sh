#!/usr/bin/env bash
# Sicherung von Datenbank und abgelegten Dateien.
#
#     deploy/backup.sh
#
# Legt unter /opt/backups/{{NAME}} zwei Dateien je Lauf ab: den Datenbankabzug
# im eigenen Format (mit pg_restore einspielbar, auch selektiv) und ein Archiv
# des Ablagebands. Ältere Stände als vierzehn Tage werden entfernt.
#
# Erfolgreich ist der Lauf nur, wenn beide Dateien am Ende nicht leer sind —
# eine leere Sicherung ist schlimmer als keine, weil sie eine vortäuscht.
# deploy/update.sh bricht ab, wenn dieses Skript nicht sauber endet.

set -euo pipefail

cd "$(dirname "$0")/.."

ZIEL="/opt/backups/{{NAME}}"
AUFBEWAHRUNG_TAGE=14
VOLUME="{{NAME}}_app_storage"

meldung() { printf '\n== %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

[ -f .env ] || abbruch "Die .env fehlt — ohne sie ist weder Benutzer noch Datenbank bekannt."

set -a
# shellcheck disable=SC1091
source .env
set +a

mkdir -p "$ZIEL"
stempel="$(date +%Y-%m-%d-%H%M%S)"
abzug="${ZIEL}/${stempel}.dump"
archiv="${ZIEL}/${stempel}-storage.tar.gz"

# ------------------------------------------------------------------ Datenbank
meldung "Datenbank sichern"
docker compose exec -T db pg_dump -U "$DB_USERNAME" -d "$DB_DATABASE" -Fc > "$abzug" \
    || abbruch "pg_dump ist gescheitert. Läuft der Container 'db'?"

[ -s "$abzug" ] || abbruch "Der Datenbankabzug ist leer: $abzug"

# ------------------------------------------------------------------- Ablagen
meldung "Abgelegte Dateien sichern"
docker run --rm \
    -v "${VOLUME}:/data:ro" \
    -v "${ZIEL}:/backup" \
    alpine:3 tar -czf "/backup/${stempel}-storage.tar.gz" -C /data . \
    || abbruch "Das Archiv des Ablagebands ist gescheitert."

[ -s "$archiv" ] || abbruch "Das Archiv des Ablagebands ist leer: $archiv"

# ---------------------------------------------------------------- Aufbewahren
meldung "Alte Stände entfernen (älter als ${AUFBEWAHRUNG_TAGE} Tage)"
find "$ZIEL" -maxdepth 1 -type f \( -name '*.dump' -o -name '*-storage.tar.gz' \) \
    -mtime "+${AUFBEWAHRUNG_TAGE}" -print -delete

meldung "Sicherung fertig"
ls -lh "$abzug" "$archiv"
