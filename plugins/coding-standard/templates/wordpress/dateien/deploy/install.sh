#!/usr/bin/env bash
# Erstinstallation von {{NAME}} auf einem Server.
#
#     deploy/install.sh
#
# Setzt voraus: Docker mit Compose v2, das Netz `edge` und einen Edge-Caddy, der auf
# :80 und :443 lauscht (siehe Skill `edge-proxy`). Die `.env` muss bereits daneben
# liegen — sie kommt aus dem KeePassXC-Tresor, nicht aus dem Repository.
#
# Gebaut wird hier nichts. Das Abbild kommt aus GHCR, in der Fassung, die APP_VERSION
# in der `.env` nennt. Ist WordPress in der Datenbank noch nicht eingerichtet, macht das
# Skript die Erstinstallation: Admin-Konto mit erzeugtem Passwort (wird genau einmal
# ausgegeben), Deutsch, Zeitzone, Permalinks, Kommentare aus, Beispielinhalt weg,
# Startseite sowie leere Seiten für Impressum und Datenschutz, Suchmaschinen noch
# gesperrt. Ein zweiter Aufruf lässt den Bestand in Ruhe.

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

# wp-cli im Anwendungscontainer; läuft dort als www-data.
wpcli() { docker compose exec -T app wp "$@"; }

# ---------------------------------------------------------------- Vorprüfung
meldung "Vorprüfung"

command -v docker >/dev/null 2>&1 || abbruch "Docker ist nicht installiert."
docker compose version >/dev/null 2>&1 || abbruch "Docker Compose v2 fehlt."
docker network inspect edge >/dev/null 2>&1 \
    || abbruch "Das Netz 'edge' fehlt. Zuerst den Edge-Proxy einrichten."

lauscht_auf 80 && lauscht_auf 443 \
    || abbruch "Auf :80 und :443 lauscht kein Edge-Caddy. Ohne ihn ist die Site nicht erreichbar."

[ -f compose.yaml ] || abbruch "compose.yaml fehlt in $ziel."
echo "Zielverzeichnis: $ziel"

# ------------------------------------------------------------------- Registry
meldung "Anmeldung an der Registry"

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

# Leere Pflichtwerte fallen hier auf, nicht erst als leere Site oder als Admin ohne Mail.
for s in WP_HOME WP_SITE_TITLE WP_ADMIN_USER WP_ADMIN_EMAIL DB_NAME DB_USER DB_PASSWORD \
         AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY \
         AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
    [ -n "${!s:-}" ] || abbruch "$s ist in der .env leer."
done
[ "$WP_ADMIN_USER" != "admin" ] || abbruch "WP_ADMIN_USER darf nicht 'admin' heißen — das ist der erste Versuch jedes Angreifers."
case "$WP_HOME" in
    https://*) ;;
    *) abbruch "WP_HOME muss mit https:// beginnen (hinter dem Edge-Caddy läuft alles verschlüsselt): $WP_HOME" ;;
esac

# ------------------------------------------------------------------- Abbilder
meldung "Abbilder laden (Fassung ${APP_VERSION})"
docker compose pull || { anmeldehinweis; abbruch "Das Abbild ließ sich nicht laden."; }

# ---------------------------------------------------------------------- Start
meldung "Verbund starten"
docker compose up -d --wait

# ------------------------------------------------------------ Erstinstallation
if wpcli core is-installed >/dev/null 2>&1; then
    meldung "WordPress ist bereits eingerichtet — der Bestand bleibt unberührt."
else
    meldung "WordPress einrichten"

    # Das Passwort geht über stdin in den Container (--prompt), nie als Argument: Es
    # stünde sonst in Prozessliste und Verlauf.
    passwort="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24 || true)"
    [ "${#passwort}" -eq 24 ] || abbruch "Passwort konnte nicht erzeugt werden."

    # wp-cli wiederholt in diesem Modus die Eingabe auf stdout — deshalb still; das
    # Passwort steht einmal am Ende dieses Skripts.
    printf '%s\n' "$passwort" | wpcli core install \
        --url="$WP_HOME" --title="$WP_SITE_TITLE" \
        --admin_user="$WP_ADMIN_USER" --admin_email="$WP_ADMIN_EMAIL" \
        --prompt=admin_password --skip-email >/dev/null \
        || abbruch "wp core install ist gescheitert. 'docker compose logs app' zeigt warum."
    echo "WordPress ist eingerichtet."

    # Deutsch — das Sprachpaket liegt im Abbild (docker/sprachpakete.php).
    wpcli site switch-language de_DE \
        || echo "Hinweis: Sprachpaket de_DE nicht im Abbild — die Oberfläche bleibt Englisch."

    # Zeit, Adressen, Kommentare, Sichtbarkeit.
    wpcli option update timezone_string 'Europe/Vienna'
    wpcli option update date_format 'j. F Y'
    wpcli option update time_format 'H:i'
    wpcli option update start_of_week 1
    wpcli option update default_comment_status closed
    wpcli option update default_ping_status closed
    wpcli option update blog_public 0
    wpcli rewrite structure '/%postname%/'

    # Beispielinhalt weg; Startseite und Pflichtseiten hin (leer — Inhalt kommt vom
    # Redakteur; ohne Impressum und Datenschutzerklärung geht die Site nicht online).
    beispiele="$(wpcli post list --post_type=post,page --post_status=any --format=ids)"
    [ -z "$beispiele" ] || wpcli post delete $beispiele --force >/dev/null
    kommentare="$(wpcli comment list --format=ids)"
    [ -z "$kommentare" ] || wpcli comment delete $kommentare --force >/dev/null

    leer='<!-- wp:paragraph --><p>Inhalt folgt.</p><!-- /wp:paragraph -->'
    start="$(wpcli post create --post_type=page --post_status=publish --porcelain \
        --post_title='Startseite' --post_name='startseite' --post_content="$leer")"
    wpcli post create --post_type=page --post_status=publish --porcelain \
        --post_title='Impressum' --post_name='impressum' --post_content="$leer" >/dev/null
    datenschutz="$(wpcli post create --post_type=page --post_status=publish --porcelain \
        --post_title='Datenschutzerklärung' --post_name='datenschutz' --post_content="$leer")"
    wpcli option update show_on_front page
    wpcli option update page_on_front "$start"
    wpcli option update wp_page_for_privacy_policy "$datenschutz"

    wpcli theme is-active site >/dev/null 2>&1 || wpcli theme activate site

    cat <<EOF

Admin-Zugang — jetzt in den KeePassXC-Tresor legen, es wird nicht noch einmal angezeigt:
    Anmeldung:  ${WP_HOME}/wp/wp-login.php
    Benutzer:   ${WP_ADMIN_USER}
    Passwort:   ${passwort}

Die Site ist für Suchmaschinen gesperrt. Freigeben, sobald Inhalt, Impressum und
Datenschutzerklärung stehen:  docker compose exec app wp option update blog_public 1
EOF
fi

# -------------------------------------------------------------------- Zustand
meldung "Zustand prüfen"
antwort="$(docker compose exec -T app curl -fsS http://127.0.0.1:8080/healthz || true)"
case "$antwort" in
    *'"status":"ok"'*) echo "Zustandsbericht: in Ordnung." ;;
    *) abbruch "Der Zustandsbericht unter /healthz antwortet nicht wie erwartet: ${antwort:-keine Antwort}. 'docker compose logs app' zeigt warum." ;;
esac

fassung="$(docker compose exec -T app php -r 'echo getenv("APP_IMAGE_VERSION");')"
meldung "Fertig — es läuft Fassung ${fassung}"
echo "Erreichbar unter ${WP_HOME}"
