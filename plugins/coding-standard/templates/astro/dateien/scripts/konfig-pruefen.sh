#!/usr/bin/env bash
# konfig-pruefen.sh — sichere Standardkonfiguration im Repo: Geheimnisse haben in .env.example
# keinen Wert, Debug ist aus, production ist die Vorgabe, keine Debug-Werkzeuge in der
# Auslieferung, im öffentlichen Ordner nur index.php, nichts Vertrauliches im Repo; dazu die
# KI-Transparenz (docs/ki-modelle.md bei ausgelieferter KI-Bibliothek) und der Meldeweg für
# Schwachstellen (SECURITY.md, security.txt mit gültigem Ablauf).
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

# json_schluessel <datei> <block> — die Schlüssel eines JSON-Blocks wie "require" oder
# "dependencies", mehrzeilig, einzeilig ({"a": "1", "b": "2"}) oder leer ({}). Ein leerer oder
# einzeiliger Block darf nicht den folgenden (require-dev, devDependencies) einlesen. Der Name wird
# mit Anführungszeichen gesucht: "dependencies" trifft weder "devDependencies" noch
# "peerDependencies", "require" nicht "require-dev".
json_schluessel() {
    awk -v b="\"$2\"" '
        !f { i = index($0, b); if (!i) next
             rest = substr($0, i + length(b))
             if (rest !~ /^[[:space:]]*:[[:space:]]*\{/) next
             sub(/^[[:space:]]*:[[:space:]]*\{/, "", rest); f = 1; $0 = rest }
        f  { e = index($0, "}"); teil = e ? substr($0, 1, e - 1) : $0
             while (match(teil, /"[^"]+"[[:space:]]*:/)) {
                 n = substr(teil, RSTART + 1, RLENGTH - 1); sub(/"[[:space:]]*:$/, "", n); print n
                 teil = substr(teil, RSTART + RLENGTH)
             }
             if (e) exit }
    ' "$1"
}
# require <composer.json> — Paketnamen aus "require" (nicht require-dev)
require_pakete() { json_schluessel "$1" require; }

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

# --- KI-Transparenz (Kern, „Arbeiten mit KI“): Liefert das Produkt eine KI-Bibliothek aus, stehen
# Modelle, Rolle und Kennzeichnung in docs/ki-modelle.md. Gezählt werden nur ausgelieferte
# Abhängigkeiten (composer require, package.json dependencies, requirements.txt samt -r) — ein
# Entwicklungswerkzeug ist keine KI-Funktion des Produkts. Erkannt werden bekannte Bibliotheken;
# was die Liste nicht kennt, fällt dem Review zu.
ki=""
if [ -f composer.json ]; then
    ki="$ki $(require_pakete composer.json | grep -xE 'openai-php/(client|laravel)|prism-php/prism|echolabsdev/prism|theodo-group/llphant|anthropic-ai/[a-z0-9-]+|mozex/anthropic-php|google-gemini-php/[a-z0-9-]+' | tr '\n' ' ' || true)"
fi
if [ -f package.json ]; then
    ki="$ki $(json_schluessel package.json dependencies \
        | grep -xE 'openai|ai|@ai-sdk/[a-z0-9-]+|@anthropic-ai/sdk|langchain|@langchain/[a-z0-9-]+|@google/genai|@google/generative-ai|@mistralai/mistralai|cohere-ai|ollama|groq-sdk|@azure/openai|@huggingface/(inference|transformers)' | tr '\n' ' ' || true)"
fi
if [ -f requirements.txt ]; then
    # Eine Ebene -r mitlesen; #egg=<name> nennt das Paket einer VCS-Zeile; ein Kommentar beginnt
    # nur nach Leerraum (pip), ein # in einer URL ist keiner; Namen nach PEP 503 vereinheitlicht.
    anforderungen="requirements.txt $(sed -nE 's/^[[:space:]]*-r[[:space:]]+([^[:space:]]+).*/\1/p' requirements.txt | tr -d '\r' | tr '\n' ' ')"
    # shellcheck disable=SC2086 # die Liste soll in Dateinamen zerfallen
    ki="$ki $(cat $anforderungen 2>/dev/null | sed -E 's/\r$//; s/.*#egg=([A-Za-z0-9._-]+).*/\1/; s/(^|[[:space:]])#.*//; s/[<>=!~;[[:space:]@].*//' \
        | tr '[:upper:]' '[:lower:]' | tr '._' '--' \
        | grep -xE 'openai|openai-agents|anthropic|langchain(-[a-z0-9-]+)?|llama-index(-[a-z0-9-]+)?|google-genai|google-generativeai|mistralai|cohere|ollama|groq|litellm|transformers|sentence-transformers|llama-cpp-python' | tr '\n' ' ' || true)"
fi
ki="$(printf '%s' "$ki" | tr -s ' ' | sed 's/^ //; s/ $//')"
if [ -n "$ki" ]; then
    if [ -f docs/ki-modelle.md ]; then
        ok "KI-Bibliothek ($ki) und docs/ki-modelle.md"
    else
        befund "KI-Bibliothek ($ki) ohne docs/ki-modelle.md — Modelle, Rolle, Risikoklasse und Kennzeichnung festhalten (Kern; Vorlage templates/dokumente/ki-modelle.md im Standard)"
    fi
fi

# --- Offenlegung (Cyber Resilience Act): Meldeweg und Supportzeitraum in SECURITY.md, der
# maschinenlesbare Kontakt in security.txt (RFC 9116). Ohne beides geht eine Meldung ins Leere
# oder in ein öffentliches Issue. Den Supportzeitraum legt jedes Projekt selbst fest — bis dahin
# ein Hinweis, kein Befund; /release hält vor dem Tag an.
if [ -f SECURITY.md ]; then
    if ! grep -q '^\*\*Supportzeitraum:\*\*' SECURITY.md; then
        hinweis "SECURITY.md: Angabe **Supportzeitraum:** fehlt — Pflichtangabe vor dem ersten Release"
    elif grep -qi 'noch festzulegen' SECURITY.md; then
        hinweis "SECURITY.md: Supportzeitraum oder unterstützte Fassungen noch festzulegen — Pflichtangabe vor dem ersten Release"
    else
        ok "SECURITY.md: Meldeweg und Supportzeitraum"
    fi
else
    befund "SECURITY.md fehlt — Meldeweg für Schwachstellen und Supportzeitraum (Vorlage templates/repo/SECURITY.md im Standard)"
fi

# tag_zahl <JJJJ-MM-TT> — grob in Tagen; genügt für „läuft in etwa einem Monat ab“.
tag_zahl() { printf '%s' $(( 10#${1:0:4} * 372 + 10#${1:5:2} * 31 + 10#${1:8:2} )); }

securitytxt=""
if [ -f artisan ] || [ -f astro.config.mjs ]; then securitytxt=public/.well-known/security.txt; fi
if [ -f wp-cli.yml ]; then securitytxt=web/.well-known/security.txt; fi
if [ -f app/main.py ]; then securitytxt=app/security.txt; fi
if [ -n "$securitytxt" ]; then
    if [ ! -f "$securitytxt" ]; then
        befund "$securitytxt fehlt — Kontakt für Sicherheitsmeldungen nach RFC 9116 (Contact, Expires)"
    else
        vorher=$befunde
        grep -q '^Contact: ' "$securitytxt" || befund "$securitytxt: Contact fehlt"
        # RFC 9116: Expires genau einmal. Nur Monat 01–12 und Tag 01–31 gelten als Datum.
        anzahl="$(grep -c '^Expires:' "$securitytxt" || true)"
        # sed -E statt \| — die Alternative in BRE kennt das sed von macOS nicht.
        ablauf="$(tr -d '\r' < "$securitytxt" | sed -nE 's/^Expires: *([0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01]))T[0-9].*/\1/p' | head -1)"
        heute="$(date -u +%Y-%m-%d)"
        if [ "$anzahl" -gt 1 ]; then
            befund "$securitytxt: Expires steht $anzahl-mal da — genau einmal (RFC 9116)"
        elif [ -z "$ablauf" ]; then
            befund "$securitytxt: Expires fehlt oder ist kein Zeitpunkt (JJJJ-MM-TTThh:mm:ssZ)"
        elif [[ ! "$ablauf" > "$heute" ]]; then
            befund "$securitytxt: abgelaufen am $ablauf — Expires neu setzen, höchstens ein Jahr voraus"
        elif [ $(( $(tag_zahl "$ablauf") - $(tag_zahl "$heute") )) -lt 31 ]; then
            hinweis "$securitytxt: läuft am $ablauf ab — Expires jetzt erneuern, höchstens ein Jahr voraus"
        elif [ $(( $(tag_zahl "$ablauf") - $(tag_zahl "$heute") )) -gt 372 ]; then
            hinweis "$securitytxt: Expires am $ablauf liegt mehr als ein Jahr voraus — RFC 9116 empfiehlt weniger"
        fi
        [ "$befunde" -eq "$vorher" ] && ok "$securitytxt: Contact und Expires ($ablauf)"
    fi
fi

if [ "$befunde" -ne 0 ]; then
    printf 'Konfiguration: %s Befund(e).\n' "$befunde" >&2
    exit 1
fi
echo "Konfiguration: sauber."
