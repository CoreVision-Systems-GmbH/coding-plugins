#!/usr/bin/env bash
# Dev-Instanz von {{NAME}} auf dem Dev-Server: baut aus dem Arbeitsstand dieses Ordners, startet
# den Verbund mit eigener Datenbank und macht ihn unter https://dev.<APP_DOMAIN> erreichbar —
# über den Edge-Caddy des Servers, nur im Tailnet.
#
#     deploy/dev.sh up       bauen, starten, Site anschließen — nach jeder Änderung erneut
#     deploy/dev.sh down     anhalten (Daten bleiben)
#     deploy/dev.sh logs     Protokoll folgen
#     deploy/dev.sh status   Container und Adresse
#
# Setzt voraus: den Dev-Server (setup-server.sh --rolle dev) und eine .env neben compose.yaml
# mit Dev-Werten (aus .env.example; Geheimnisse aus dem Tresor; APP_DOMAIN gesetzt).
# Nur für den Dev-Server: Auf Prod läuft ausschließlich ein Release (sudo rollout …).
# Rückweg: deploy/dev.sh down; die Site entfernt sudo edge-site remove <APP_DOMAIN>.

set -euo pipefail

cd "$(dirname "$0")/.."
NAME="{{NAME}}"

abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

rolle="$(sed -n 's/^ROLLE=//p' /etc/corevision/server.env 2>/dev/null | head -1 || true)"
[ "$rolle" = dev ] || abbruch "deploy/dev.sh läuft nur auf dem Dev-Server (setup-server.sh --rolle dev)."

if [ ! -f .env ]; then
    cp .env.example .env
    abbruch ".env aus .env.example angelegt — Dev-Werte eintragen (APP_DOMAIN, Geheimnisse aus dem Tresor), dann erneut."
fi
domain="$(sed -n 's/^APP_DOMAIN=//p' .env | head -1 | tr -d '\r' || true)"
case "$domain" in ""|*.invalid) abbruch "APP_DOMAIN fehlt in .env (Hostname ohne https://, z. B. app.example.at)." ;; esac

# Projektname und Container-Namen der Dev-Instanz sind eigene (…-dev): eigene Volumes, eigene DB.
compose() {
    APP_VERSION=dev docker compose -p "$NAME-dev" \
        -f compose.yaml -f compose.build.yaml -f compose.dev.yaml "$@"
}
edge_site() { if [ "$(id -u)" -eq 0 ]; then edge-site "$@"; else sudo edge-site "$@"; fi; }

case "${1:-}" in
    up)
        compose up -d --build --wait
        # Laravel: Schema der Dev-Datenbank auf den Arbeitsstand bringen.
        if [ -f artisan ]; then compose exec -T app php artisan migrate --force; fi
        if edge_site list | grep -q "^$domain "; then
            printf 'Site besteht: https://dev.%s\n' "$domain"
        else
            edge_site add "$domain" "$NAME-dev-app:8080"
        fi
        printf 'Dev-Instanz läuft: https://dev.%s\n' "$domain"
        ;;
    down)   compose down ;;
    logs)   compose logs -f --tail 100 ;;
    status) compose ps; printf 'Adresse: https://dev.%s\n' "$domain" ;;
    *)      printf 'Aufruf: deploy/dev.sh up|down|logs|status\n' >&2; exit 1 ;;
esac
