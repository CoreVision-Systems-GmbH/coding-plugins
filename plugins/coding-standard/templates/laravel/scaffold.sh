#!/usr/bin/env bash
# Gerüst für den Stack laravel.
#
# Wird von scripts/projekt-neu.sh zweimal aufgerufen:
#   PHASE=geruest     — Zielordner ist leer oder fehlt; hier läuft der Installer.
#   PHASE=einrichten  — die Vorlagen liegen bereits im Zielordner.
#
# Umgebung: NAME DIR OWNER IMAGE PURPOSE ENV_PREFIX PHASE

set -euo pipefail

meldung() { printf '   %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

# --------------------------------------------------------- Werkzeuge auflösen
# Unter Windows liegen Composer und der Laravel-Installer als .phar neben einer
# .bat im Herd-Verzeichnis. Die .bat sucht sich ihr PHP selbst — und findet unter
# Umständen die herd-lite-Fassung ohne intl. Deshalb wird das PHP hier bestimmt
# und der .phar direkt damit aufgerufen.
php_finden() {
    local k
    for k in "$HOME/.config/herd/bin/php84/php.exe" "$(command -v php || true)"; do
        [ -n "$k" ] && [ -x "$k" ] || continue
        "$k" -m 2>/dev/null | grep -qix 'intl' && { printf '%s' "$k"; return 0; }
    done
    return 1
}

PHP="$(php_finden || true)"
[ -n "$PHP" ] || abbruch \
"Kein PHP mit der Erweiterung 'intl' gefunden. Filament verlangt sie; ohne sie enden
Filament-Tests mit HTTP 500. Unter Windows: C:/Users/<benutzer>/.config/herd/bin/php84/php.exe.
Prüfen mit: php -m | grep intl"

composer_lauf() {
    if [ -f "$HOME/.config/herd/bin/composer.phar" ]; then
        "$PHP" "$HOME/.config/herd/bin/composer.phar" "$@"
    elif command -v composer >/dev/null 2>&1; then
        composer "$@"
    else
        composer.bat "$@"
    fi
}

artisan() { "$PHP" artisan "$@"; }

# ================================================================== PHASE 1
if [ "$PHASE" = "geruest" ]; then
    eltern="$(dirname "$DIR")"
    basis="$(basename "$DIR")"

    # `laravel new` legt den Ordner selbst an und bricht ab, wenn er schon da
    # ist — auch wenn er leer ist.
    [ -d "$DIR" ] && rmdir "$DIR"
    mkdir -p "$eltern"

    meldung "laravel new $basis (React, PostgreSQL, Pest) — das dauert einige Minuten"
    (
        cd "$eltern"
        if [ -f "$HOME/.config/herd/bin/laravel.phar" ]; then
            "$PHP" "$HOME/.config/herd/bin/laravel.phar" new "$basis" \
                --react --database=pgsql --pest --npm --no-interaction
        elif command -v laravel >/dev/null 2>&1; then
            laravel new "$basis" --react --database=pgsql --pest --npm --no-interaction
        else
            laravel.bat new "$basis" --react --database=pgsql --pest --npm --no-interaction
        fi
    )

    cd "$DIR"

    meldung "Filament 5 einrichten"
    composer_lauf require 'filament/filament:^5.8' -W --no-interaction
    artisan filament:install --panels --no-interaction

    meldung "Laravel Boost dazunehmen"
    composer_lauf require laravel/boost --dev --no-interaction

    # boost:install ist auf Rückfragen ausgelegt. Läuft es nicht durch, ist das
    # kein Grund, das ganze Gerüst zu verwerfen — der Aufruf steht dann in der
    # Nacharbeit.
    meldung "boost:install versuchen (nicht blockierend)"
    if artisan boost:install --no-interaction </dev/null >/dev/null 2>&1; then
        meldung "boost:install: durchgelaufen"
    else
        printf 'NACHARBEIT: php artisan boost:install von Hand ausführen (interaktiv).\n' \
            >> "$DIR/.projekt-neu-nacharbeit"
        meldung "boost:install: nicht durchgelaufen — als Nacharbeit vermerkt"
    fi

    exit 0
fi

# ================================================================== PHASE 2
cd "$DIR"

meldung "Composer-Abhängigkeiten und Frontend einrichten"
composer_lauf install --no-interaction
[ -f .env ] || cp .env.example .env
artisan key:generate --ansi
npm install --no-audit --no-fund

meldung "Gerüst steht. Die Firmenstandard-Nacharbeit macht /projekt-neu im Anschluss."
