#!/bin/sh
# Startvorbereitung des Anwendungscontainers.
#
# Der Einstiegspunkt gilt für beide Rollen: Webserver und Warteschlangen-
# Arbeiter. Wanderungen und Zwischenspeicher werden nur von der Webrolle
# angefasst, damit zwei gleichzeitig startende Container nicht dieselbe
# Wanderung ausführen.

set -e

wait_for_database() {
    echo "Warte auf die Datenbank ..."
    i=0
    until php artisan db:monitor --max=1 >/dev/null 2>&1; do
        i=$((i + 1))
        if [ "$i" -ge 60 ]; then
            echo "Datenbank nach 60 Versuchen nicht erreichbar — Abbruch." >&2
            exit 1
        fi
        sleep 2
    done
    echo "Datenbank erreichbar."
}

if [ "$CONTAINER_ROLE" = "worker" ]; then
    wait_for_database
    exec "$@"
fi

wait_for_database

echo "Führe ausstehende Wanderungen aus ..."
php artisan migrate --force --no-interaction

echo "Erzeuge Zwischenspeicher ..."
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

# Die Verknüpfung public/storage kommt seit der Härtung aus dem Dockerfile (das
# Wurzeldateisystem ist schreibgeschützt); der Aufruf bleibt für ältere Abbilder
# und fällt still aus, wenn sie schon besteht.
php artisan storage:link --quiet 2>/dev/null || true

exec "$@"
