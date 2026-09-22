#!/usr/bin/env bash
# Erstinstallation von {{NAME}} auf einem Server.
#
#     deploy/install.sh
#
# Setzt voraus: Docker mit Compose v2, das Netz `edge` und einen Edge-Caddy,
# der auf :80 und :443 lauscht (setup-server.sh aus dem Standard). Die `.env` muss
# bereits daneben liegen — sie kommt aus dem KeePassXC-Tresor, nicht aus dem
# Repository.
#
# Gebaut wird hier nichts. Das Abbild kommt aus GHCR, in der Fassung, die
# APP_VERSION in der `.env` nennt.

set -euo pipefail

cd "$(dirname "$0")/.."
ziel="$(pwd)"

meldung() { printf '\n== %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

lauscht_auf() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltnH 2>/dev/null | awk '{ print $4 }' | grep -qE ":$1\$"
    else
        docker ps --format '{{.Ports}}' | grep -q ":$1->"
    fi
}

# ---------------------------------------------------------------- Vorprüfung
meldung "Vorprüfung"

command -v docker >/dev/null 2>&1 || abbruch "Docker ist nicht installiert."
docker compose version >/dev/null 2>&1 || abbruch "Docker Compose v2 fehlt."
docker network inspect edge >/dev/null 2>&1 \
    || abbruch "Das Netz 'edge' fehlt. Zuerst den Edge-Proxy einrichten."

# Server nach dem Standard (setup-server.sh): Der Edge heißt edge-caddy. Sonst genügt ein
# beliebiger Proxy auf :80/:443.
if [ -f /etc/corevision/server.env ]; then
    docker ps --format '{{.Names}}' | grep -qx edge-caddy \
        || abbruch "Der Edge-Caddy läuft nicht. Zuerst setup-server.sh (EINRICHTUNG.md, Teil C)."
else
    lauscht_auf 80 && lauscht_auf 443 \
        || abbruch "Auf :80 und :443 lauscht kein Edge-Caddy. Ohne ihn ist der Dienst nicht erreichbar."
fi

[ -f compose.yaml ] || abbruch "compose.yaml fehlt in $ziel."
echo "Zielverzeichnis: $ziel"

# ------------------------------------------------------------------- Registry
anmeldehinweis() {
    echo "Mit einem Token anmelden, das nur 'read:packages' darf" >&2
    echo "(Ablage im KeePassXC-Tresor):" >&2
    echo >&2
    echo "    echo \"\$TOKEN\" | docker login ghcr.io -u <maschinenkonto> --password-stdin" >&2
    echo >&2
}

if ! grep -q 'ghcr.io' "${DOCKER_CONFIG:-$HOME/.docker}/config.json" 2>/dev/null; then
    echo "Hinweis: In der Docker-Konfiguration ist keine Anmeldung an ghcr.io hinterlegt."
    anmeldehinweis
fi

# ------------------------------------------------------------------------ ENV
meldung "Umgebungsdatei prüfen"

[ -f .env ] || abbruch "Die .env fehlt. Sie kommt aus dem KeePassXC-Tresor und gehört nie ins Repository."

fehlend=""
while IFS= read -r schluessel; do
    grep -qE "^[[:space:]]*${schluessel}=" .env || fehlend="${fehlend} ${schluessel}"
done < <(grep -oE '^[A-Z_][A-Z0-9_]*=' .env.example | tr -d '=' | sort -u)

if [ -n "$fehlend" ]; then
    echo "In der .env fehlen Schlüssel aus .env.example:" >&2
    for s in $fehlend; do echo "  - $s" >&2; done
    abbruch "Erst die fehlenden Schlüssel ergänzen, dann erneut aufrufen."
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

chmod 600 .env

# ---------------------------------------------------------------------- Start
meldung "Abbild laden (Fassung ${APP_VERSION})"
docker compose pull || { anmeldehinweis; abbruch "Das Abbild ließ sich nicht laden."; }

meldung "Verbund starten"
docker compose up -d --wait

# -------------------------------------------------------------------- Zustand
meldung "Zustand prüfen"
docker compose exec -T app curl -fsS http://127.0.0.1:8080/healthz \
    || abbruch "Der Zustandsbericht unter /healthz antwortet nicht. 'docker compose logs app' zeigt warum."

# -------------------------------------------------------------------- Adresse
# Server nach dem Standard: Die Site wird über edge-site an den Edge-Caddy angeschlossen
# (DNS-Eintrag, Zertifikat über DNS-01). Ohne setup-server.sh trägt man sie im Proxy von Hand ein.
if [ -f /etc/corevision/server.env ] && command -v edge-site >/dev/null 2>&1; then
    domain="$(sed -n 's/^APP_DOMAIN=//p' .env | head -1 | tr -d '\r')"
    if [ -n "$domain" ] && [ "${domain%.invalid}" = "$domain" ]; then
        meldung "An den Edge-Caddy anschließen ($domain)"
        if [ "$(id -u)" -eq 0 ]; then edge-site add "$domain" "{{NAME}}-app:8080"
        else sudo edge-site add "$domain" "{{NAME}}-app:8080"; fi
    else
        echo "APP_DOMAIN fehlt in .env — später: sudo edge-site add <host> {{NAME}}-app:8080"
    fi
else
    echo "Den Hostnamen im Edge-Proxy eintragen: Ziel {{NAME}}-app:8080 im Netz edge."
fi

meldung "Fertig"
