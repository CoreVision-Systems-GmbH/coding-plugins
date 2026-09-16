#!/usr/bin/env bash
# Gerüst für den Stack wordpress.
#
# Wird von scripts/projekt-neu.sh zweimal aufgerufen:
#   PHASE=geruest     — Zielordner ist leer oder fehlt; hier wird nur angelegt.
#   PHASE=einrichten  — die Vorlagen liegen bereits im Zielordner.
#
# Es gibt keinen Installer: Das Gerüst kommt vollständig aus templates/wordpress/dateien
# (Bedrock-Layout mit eigener composer.json). Diese Phase installiert die Abhängigkeiten
# — WordPress selbst kommt dabei als Composer-Paket nach web/wp — und lässt einmal alle
# Prüfungen laufen. Ein Gerüst, das nicht grün ist, wird gar nicht erst ausgeliefert.
#
# Umgebung: NAME DIR OWNER IMAGE PURPOSE ENV_PREFIX PHASE

set -euo pipefail

meldung() { printf '   %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

if [ "$PHASE" = "geruest" ]; then
    mkdir -p "$DIR"
    exit 0
fi

cd "$DIR"

# --------------------------------------------------------- Werkzeuge auflösen
# Unter Windows liegt Composer als .phar neben einer .bat im Herd-Verzeichnis; die
# .bat sucht sich ihr PHP selbst. Deshalb wird das PHP hier bestimmt — mindestens
# 8.4, wie im Abbild — und der .phar direkt damit aufgerufen.
php_finden() {
    local k
    for k in "$HOME/.config/herd/bin/php84/php.exe" "$(command -v php || true)"; do
        [ -n "$k" ] && [ -x "$k" ] || continue
        "$k" -r 'exit(PHP_VERSION_ID >= 80400 ? 0 : 1);' 2>/dev/null && { printf '%s' "$k"; return 0; }
    done
    return 1
}

PHP="$(php_finden || true)"
[ -n "$PHP" ] || abbruch \
"Kein PHP 8.4 oder neuer gefunden — composer.json verlangt >= 8.4, das Abbild hat 8.4.
Unter Windows: C:/Users/<benutzer>/.config/herd/bin/php84/php.exe. Prüfen mit: php --version"

composer_lauf() {
    if [ -f "$HOME/.config/herd/bin/composer.phar" ]; then
        "$PHP" "$HOME/.config/herd/bin/composer.phar" "$@"
    elif command -v composer >/dev/null 2>&1; then
        composer "$@"
    else
        composer.bat "$@"
    fi
}

meldung "composer install — erzeugt composer.lock, lädt WordPress nach web/wp"
composer_lauf install --no-interaction --no-progress

meldung "composer check (Coding-Standards, statische Analyse, Strukturprüfung)"
composer_lauf check

# Welche Domain die Site bekommt, weiß das Skript nicht; die Platzhalter-Domain aus
# .env.example bleibt bewusst stehen. Die Pflichtseiten legt deploy/install.sh leer an.
printf '%s\n' \
    "WP_HOME in der .env der Instanz auf die echte Domain setzen (Vorlage: https://$NAME.invalid) — nur mit ihr stimmen Links, Anmeldung und Medienadressen." \
    'Impressum und Datenschutzerklärung befüllen — deploy/install.sh legt beide Seiten leer an; ohne Inhalt geht die Site nicht online.' \
    >> "$DIR/.projekt-neu-nacharbeit"

meldung "Gerüst steht und ist grün."
