#!/bin/sh
# Startvorbereitung: auf die Datenbank warten, dann den eigentlichen Prozess starten.
#
# Gilt für beide Rollen (app, cron). Schema-Updates macht bewusst nicht der Start,
# sondern deploy/update.sh (wp core update-db) — ein Container, der beim Start das
# Schema hebt, tut das ohne Sicherung.

set -e

echo "Warte auf die Datenbank ${DB_HOST:-db} ..."
i=0
until php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $db = @new mysqli(
        (string) (getenv("DB_HOST") ?: "db"),
        (string) getenv("DB_USER"),
        (string) getenv("DB_PASSWORD"),
        (string) getenv("DB_NAME")
    );
    exit($db->connect_errno ? 1 : 0);
' >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 60 ]; then
        echo "Datenbank nach 60 Versuchen nicht erreichbar — Abbruch." >&2
        exit 1
    fi
    sleep 2
done
echo "Datenbank erreichbar."

exec "$@"
