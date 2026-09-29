#!/bin/sh
# Startvorbereitung des Anwendungscontainers.
#
# Der Einstiegspunkt gilt für beide Rollen: Webserver und Warteschlangen-
# Arbeiter. Wanderungen und Zwischenspeicher werden nur von der Webrolle
# angefasst, damit zwei gleichzeitig startende Container nicht dieselbe
# Wanderung ausführen.

set -e

# Die Ausgabe von artisan bleibt beim Warten still, beim Abbruch kommt sie mit: Jeder
# Fehler beim Booten (fehlender Cache-Pfad, kaputte .env) scheitert hier zuerst und sah
# früher aus wie eine unerreichbare Datenbank (Pilot, 2026-09-29).
wait_for_database() {
    echo "Warte auf die Datenbank ..."
    i=0
    until ausgabe="$(php artisan db:monitor --max=1 2>&1)"; do
        i=$((i + 1))
        if [ "$i" -ge 60 ]; then
            echo "Datenbankprüfung nach 60 Versuchen gescheitert — Abbruch. Letzte Ausgabe von php artisan db:monitor:" >&2
            printf '%s\n' "$ausgabe" | tail -n 20 >&2
            exit 1
        fi
        sleep 2
    done
    echo "Datenbank erreichbar."
}

# storage/framework ist ein tmpfs (compose.yaml) und beim Start leer. Laravel braucht
# storage/framework/views schon beim Booten; fehlt es, scheitert jeder artisan-Aufruf mit
# „Please provide a valid cache path.“ — und wait_for_database hielt das für eine
# unerreichbare Datenbank. Am 2026-09-29 beim ersten Start auf dem Dev-Server genau so passiert.
mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views

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
