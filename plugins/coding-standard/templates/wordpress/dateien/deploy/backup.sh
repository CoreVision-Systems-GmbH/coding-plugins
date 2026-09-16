#!/usr/bin/env bash
# Sicherung von Datenbank und Uploads.
#
#     deploy/backup.sh
#
# Legt unter /opt/backups/{{NAME}} zwei Dateien je Lauf ab: den Datenbankabzug
# (mariadb-dump, gzip) und ein Archiv der Uploads. Ältere Stände als vierzehn Tage
# werden entfernt. Die Sicherungen sind vertraulich — sie enthalten Nutzerkonten und
# die Zugangsdaten, die Plugins in wp_options ablegen — und liegen mit 600.
#
# Erfolgreich ist der Lauf nur, wenn beide Dateien am Ende nicht leer sind und der
# Abzug wirklich Tabellen enthält — eine leere Sicherung ist schlimmer als keine, weil
# sie eine vortäuscht. deploy/update.sh bricht ab, wenn dieses Skript nicht sauber endet.
#
# Einspielen (Rückweg nach einem Schema-Update):
#     set -a; source .env; set +a
#     gunzip -c /opt/backups/{{NAME}}/<stempel>.sql.gz \
#         | docker compose exec -T -e MYSQL_PWD="$DB_PASSWORD" db mariadb --user="$DB_USER" "$DB_NAME"
#     docker run --rm -v {{NAME}}_app_uploads:/data -v /opt/backups/{{NAME}}:/backup alpine:3 \
#         sh -c 'cd /data && tar -xzf /backup/<stempel>-uploads.tar.gz'

set -euo pipefail

cd "$(dirname "$0")/.."

ZIEL="/opt/backups/{{NAME}}"
AUFBEWAHRUNG_TAGE=14
VOLUME="{{NAME}}_app_uploads"

meldung() { printf '\n== %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

[ -f .env ] || abbruch "Die .env fehlt — ohne sie ist weder Benutzer noch Datenbank bekannt."

set -a
# shellcheck disable=SC1091
source .env
set +a

mkdir -p "$ZIEL"
chmod 700 "$ZIEL"
stempel="$(date +%Y-%m-%d-%H%M%S)"
abzug="${ZIEL}/${stempel}.sql.gz"
archiv="${ZIEL}/${stempel}-uploads.tar.gz"

# ------------------------------------------------------------------ Datenbank
meldung "Datenbank sichern"
# Das Passwort geht als Umgebungsvariable in den Container, nicht als Argument.
docker compose exec -T -e MYSQL_PWD="$DB_PASSWORD" db \
    mariadb-dump --single-transaction --quick --routines --triggers \
        --user="$DB_USER" "$DB_NAME" | gzip > "$abzug" \
    || abbruch "mariadb-dump ist gescheitert. Läuft der Container 'db'?"

[ -s "$abzug" ] || abbruch "Der Datenbankabzug ist leer: $abzug"
gunzip -c "$abzug" | grep -q 'CREATE TABLE' \
    || abbruch "Der Datenbankabzug enthält keine Tabellen: $abzug"
chmod 600 "$abzug"

# -------------------------------------------------------------------- Uploads
meldung "Uploads sichern"
docker run --rm \
    -v "${VOLUME}:/data:ro" \
    -v "${ZIEL}:/backup" \
    alpine:3 tar -czf "/backup/${stempel}-uploads.tar.gz" -C /data . \
    || abbruch "Das Archiv der Uploads ist gescheitert."

[ -s "$archiv" ] || abbruch "Das Archiv der Uploads ist leer: $archiv"
chmod 600 "$archiv"

# ---------------------------------------------------------------- Aufbewahren
meldung "Alte Stände entfernen (älter als ${AUFBEWAHRUNG_TAGE} Tage)"
find "$ZIEL" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name '*-uploads.tar.gz' \) \
    -mtime "+${AUFBEWAHRUNG_TAGE}" -print -delete

meldung "Sicherung fertig"
ls -lh "$abzug" "$archiv"
