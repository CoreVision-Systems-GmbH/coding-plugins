#!/usr/bin/env bash
# konfig-pruefen.sh — sichere Standardkonfiguration im Repo: Geheimnisse haben in .env.example
# keinen Wert, Debug ist aus, production ist die Vorgabe, keine Debug-Werkzeuge in der
# Auslieferung, im öffentlichen Ordner nur index.php, nichts Vertrauliches im Repo.
#
# Aufruf:   bash scripts/konfig-pruefen.sh     — Teil von `check` und des CI-Schritts „Konfiguration“
# Ändert:   nichts. Exit 0 = sauber, Exit 1 = Befunde (je eine Zeile BEFUND).
# Rückweg:  keiner nötig.
#
# Der Stack wird an seinen Dateien erkannt (artisan, wp-cli.yml, app/main.py, astro.config.mjs);
# was es nicht gibt, wird übersprungen. Die Instanz selbst (APP_ENV, APP_DEBUG der echten .env)
# prüft deploy/update.sh auf dem Server — dort liegt die .env, hier nicht.

set -euo pipefail
cd "$(dirname "$0")/.."

befunde=0
befund() { printf 'BEFUND  %s\n' "$1"; befunde=$((befunde + 1)); }
ok() { printf 'ok      %s\n' "$1"; }
hinweis() { printf 'Hinweis %s\n' "$1"; }

# zeilen <datei> — .env-Zeilen normalisiert: ohne \r, ohne „export “, ohne Leerraum um das erste
# Gleichheitszeichen. phpdotenv und compose lesen alle drei Formen, also muss die Prüfung das auch.
zeilen() { sed 's/\r$//; s/^[[:space:]]*export[[:space:]]\{1,\}//; s/^\([^=]*[^=[:space:]]\)[[:space:]]*=[[:space:]]*/\1=/' "$1"; }

# --- .env.example: das Schema — Geheimnisse ohne Wert, Debug aus, production als Vorgabe
if [ -f .env.example ]; then
    vorher=$befunde
    while IFS='=' read -r schluessel rest || [ -n "$schluessel" ]; do
        case "$schluessel" in ''|\#*) continue ;; esac
        v="$(printf '%s' "$rest" | tr -d "\r\"'")"
        case "$schluessel" in
            *PASSWORD*|*SECRET*|*TOKEN*|*SALT*|*_KEY|*PRIVATE*|*_SK|*_DSN|*CREDENTIAL*)
                case "$v" in ''|null|\<*\>|\{\{*\}\}) ;;
                    *) befund ".env.example: $schluessel trägt einen Wert — Geheimnisse bleiben hier leer (Tresor, .env der Instanz)" ;;
                esac ;;
        esac
        # Zugangsdaten in einer URL (postgres://nutzer:passwort@host) sind ein Geheimnis, egal wie der Schlüssel heißt.
        case "$v" in *://*:*@*) befund ".env.example: $schluessel trägt Zugangsdaten in der URL — Geheimnisse bleiben hier leer" ;; esac
        case "$schluessel" in
            APP_ENV|WP_ENV) [ "$v" = production ] || befund ".env.example: $schluessel=$v — Vorgabe ist production; local/development setzt die Dev-Instanz (compose.dev.yaml)" ;;
            *DEBUG) case "$v" in false|0|'') ;; *) befund ".env.example: $schluessel=$v — Vorgabe ist false; Debug-Ausgabe liefert Stacktraces samt Geheimnissen an jeden Besucher" ;; esac ;;
        esac
    done < <(zeilen .env.example)
    [ "$befunde" -eq "$vorher" ] && ok ".env.example: Geheimnisse leer, Debug aus, production als Vorgabe"
else
    befund ".env.example fehlt — das Schema der Konfiguration mit Kommentar je Schlüssel (Kern)"
fi

# --- nichts Vertrauliches im Repo: keine .env, keine Schlüssel, keine Dumps. Vor dem ersten
# `git init` (Gerüst im Bau) gibt es noch kein Repo — dann wird dieser Punkt benannt, nicht rot.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    vertraulich="$(git ls-files -- '.env' '.env.*' '*/.env' '*/.env.*' ':!.env.example' ':!*/.env.example' '*.pem' '*.key' '*.kdbx' 'id_rsa' 'id_ed25519' '*/id_rsa' '*/id_ed25519' '*.dump' '*.sql.gz' 2>/dev/null || true)"
    if [ -n "$vertraulich" ]; then
        befund "Vertrauliches im Repo: $(printf '%s' "$vertraulich" | tr '\n' ' ') — löschen und den Wert wechseln (Kern: ein Geheimnis in der Historie gilt als verbrannt)"
    else
        ok "keine .env, Schlüssel oder Dumps im Repo"
    fi
else
    hinweis "kein Git-Repo — ob Vertrauliches eingecheckt ist, prüft der nächste Lauf im Repo"
fi

# require <composer.json> — Paketnamen aus "require" (nicht require-dev)
# Ein leeres `"require": {}` auf einer Zeile darf nicht den folgenden Block (require-dev) einlesen.
require_pakete() { awk '/"require"[[:space:]]*:[[:space:]]*\{[[:space:]]*\}/{next} /"require"[[:space:]]*:/{f=1;next} f&&/^[[:space:]]*}/{exit} f' "$1" | sed -n 's/^[[:space:]]*"\([^"]*\)".*/\1/p'; }

# --- Laravel
if [ -f artisan ]; then
    vorher=$befunde
    # Auch Unterordner: public/tools/adminer.php führt PHP-FPM genauso aus.
    fremd="$(find public -type f -name '*.php' ! -path 'public/index.php' 2>/dev/null || true)"
    [ -z "$fremd" ] || befund "public/: PHP-Dateien außer index.php — Diagnoseskripte gehören nicht ins öffentliche Verzeichnis (Fehlermuster F): $(printf '%s' "$fremd" | tr '\n' ' ')"
    for p in laravel/telescope barryvdh/laravel-debugbar itsgoingd/clockwork spatie/laravel-ignition beyondcode/laravel-dump-server; do
        require_pakete composer.json | grep -qx "$p" && befund "composer.json: $p in require — Debug-Werkzeuge gehören nach require-dev (werden mit --no-dev nicht ausgeliefert)"
    done
    [ "$befunde" -eq "$vorher" ] && ok "Laravel: public/ nur index.php, keine Debug-Werkzeuge in require"
fi

# --- WordPress (Bedrock)
if [ -f wp-cli.yml ]; then
    vorher=$befunde
    fremd="$(find web -maxdepth 1 -name '*.php' ! -name index.php ! -name wp-config.php 2>/dev/null || true)"
    [ -z "$fremd" ] || befund "web/: PHP-Dateien außer index.php und wp-config.php — Diagnoseskripte gehören nicht ins öffentliche Verzeichnis: $(printf '%s' "$fremd" | tr '\n' ' ')"
    for p in wpackagist-plugin/query-monitor wpackagist-plugin/debug-bar wpackagist-plugin/wp-crontrol; do
        require_pakete composer.json | grep -qx "$p" && befund "composer.json: $p in require — Debug-Plugins nur in require-dev oder gar nicht"
    done
    if [ -f config/environments/production.php ] && grep -Eq "WP_DEBUG['\"]?[[:space:]]*,[[:space:]]*true" config/environments/production.php; then
        befund "config/environments/production.php: WP_DEBUG=true in Produktion"
    fi
    [ "$befunde" -eq "$vorher" ] && ok "WordPress: web/ nur index.php und wp-config.php, keine Debug-Plugins in require, WP_DEBUG aus"
fi

# --- FastAPI
if [ -f app/main.py ]; then
    vorher=$befunde
    if [ -f Dockerfile ] && grep -q -- '--reload' Dockerfile; then
        befund "Dockerfile: --reload gehört nicht in die Auslieferung (Entwicklungsmodus, Dateiwächter, doppelter Prozess)"
    fi
    [ "$befunde" -eq "$vorher" ] && ok "FastAPI: kein --reload im Abbild"
fi

# --- Astro: keine Laufzeit-Konfiguration, alles steht im Bau
if [ -f astro.config.mjs ] && [ -f .env.example ]; then
    vorher=$befunde
    while IFS='=' read -r schluessel rest || [ -n "$schluessel" ]; do
        case "$schluessel" in ''|\#*|APP_VERSION|APP_DOMAIN|PUBLIC_*) continue ;; esac
        befund ".env.example: $schluessel — eine statische Site hat keine Laufzeit-Konfiguration; was die Site weiß, steht im Bau (PUBLIC_*) oder gar nicht in der .env"
    done < <(zeilen .env.example)
    [ "$befunde" -eq "$vorher" ] && ok "Astro: .env.example nur APP_VERSION, APP_DOMAIN und PUBLIC_*"
fi

if [ "$befunde" -ne 0 ]; then
    printf 'Konfiguration: %s Befund(e).\n' "$befunde" >&2
    exit 1
fi
echo "Konfiguration: sauber."
