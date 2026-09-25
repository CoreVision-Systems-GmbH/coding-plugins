#!/usr/bin/env bash
# komplexitaet-pruefen.sh — Kennzahlen je Funktion: zyklomatische Komplexität ≤ 10, höchstens
# 50 Anweisungen und 12 Verzweigungen; ESLint misst zusätzlich Verschachtelung ≤ 4 und Datei
# ≤ 800 Zeilen, PHPMD die Methoden- und Klassenlänge. KI-Modelle schreiben gern
# 120-Zeilen-Funktionen mit sechs Ebenen — genau das, was niemand mehr reviewt.
#
# Aufruf:   bash scripts/komplexitaet-pruefen.sh     — Teil von `check` und der CI
# Ändert:   nichts. Bis Ende 2026 sind Befunde eine Warnung (Exit 0), ab 2027-01-01 rot (Exit 1).
# Rückweg:  keiner nötig.
#
# Werkzeuge je Sprache, wo sie im Repo liegen: Python — ruff (C901, PLR0912, PLR0915; Schwellen
# in pyproject.toml); PHP — PHPMD mit phpmd.xml (vendor/bin/phpmd); JavaScript/TypeScript —
# ESLint mit den Regeln complexity, max-depth, max-lines-per-function, max-lines. Fehlt ein
# Werkzeug, sagt das Skript das und prüft den Rest — kein stilles Grün.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(date -u +%F)" \< "2027-01-01" ]; then streng=0; else streng=1; fi
befunde=0
hinweise=0

lauf() { # <name> <befehl…> — Exit ≠ 0 zählt als Befund
    local name="$1"
    shift
    printf '\n== %s\n' "$name"
    if "$@"; then :; else befunde=$((befunde + 1)); fi
}
hinweis() { printf 'Hinweis: %s\n' "$1"; hinweise=$((hinweise + 1)); }

# Ohne Git-Repo (Gerüst vor `git init`) über find — sonst wäre eine leere Liste stilles Grün.
dateien() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git ls-files --cached --others --exclude-standard -- "$@" 2>/dev/null || true
    else
        find . \( -name node_modules -o -name vendor -o -name .venv -o -name .git \) -prune -o -type f -name "$1" -print 2>/dev/null
    fi
}
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || hinweis "kein Git-Repo — Dateien per find statt aus dem Index"

# --- Python: ruff
if [ -n "$(dateien '*.py')" ]; then
    if [ -x .venv/Scripts/python.exe ]; then py=".venv/Scripts/python.exe"
    elif [ -x .venv/bin/python ]; then py=".venv/bin/python"
    else py="$(command -v python || command -v python3 || true)"; fi
    if [ -n "$py" ] && "$py" -m ruff --version >/dev/null 2>&1; then
        lauf "ruff: Komplexität (C901), Verzweigungen (PLR0912), Anweisungen (PLR0915)" \
            "$py" -m ruff check --select C901,PLR0912,PLR0915 --no-cache .
    else
        hinweis "ruff fehlt — Python nicht geprüft (pip install ruff)"
    fi
fi

# --- PHP: PHPMD
if [ -f composer.json ]; then
    if [ -x vendor/bin/phpmd ] && [ -f phpmd.xml ]; then
        if [ -f artisan ]; then kandidaten="app"
        elif [ -f wp-cli.yml ]; then kandidaten="web/app/themes/site web/app/mu-plugins"
        else kandidaten="src"; fi
        # Nur vorhandene Ordner — ein fehlender Pfad wäre bei PHPMD ein Fehler, kein Befund.
        ziele=""
        for k in $kandidaten; do [ -d "$k" ] && ziele="${ziele:+$ziele,}$k"; done
        if [ -n "$ziele" ]; then
            lauf "PHPMD ($ziele, phpmd.xml)" vendor/bin/phpmd "$ziele" text phpmd.xml
        else
            hinweis "PHPMD: keiner der Ordner ($kandidaten) vorhanden — PHP nicht geprüft"
        fi
    else
        hinweis "PHPMD fehlt — PHP nicht geprüft (composer require --dev phpmd/phpmd; phpmd.xml aus der Vorlage)"
    fi
fi

# --- JavaScript/TypeScript: ESLint, wo es im Repo liegt
if [ -f package.json ]; then
    if [ -x node_modules/.bin/eslint ] && ls eslint.config.* >/dev/null 2>&1; then
        if [ -d resources/js ]; then ziel="resources/js"; else ziel="src"; fi
        # Die vier Regeln als error, ohne --max-warnings: Warnungen der Projektkonfiguration
        # (etwa react-hooks/exhaustive-deps) sind keine Komplexitätsbefunde.
        lauf "ESLint: complexity, max-depth, max-lines-per-function, max-lines ($ziel)" \
            node_modules/.bin/eslint --no-fix \
            --rule 'complexity: ["error", 10]' \
            --rule 'max-depth: ["error", 4]' \
            --rule 'max-lines-per-function: ["error", {"max": 50, "skipBlankLines": true, "skipComments": true}]' \
            --rule 'max-lines: ["error", {"max": 800, "skipBlankLines": true, "skipComments": true}]' \
            "$ziel"
    else
        hinweis "kein ESLint im Repo — JavaScript/TypeScript nicht geprüft"
    fi
fi

echo
if [ "$befunde" -eq 0 ]; then
    printf 'Komplexität: keine Befunde (%s Hinweis(e)).\n' "$hinweise"
    exit 0
fi
if [ "$streng" -eq 1 ]; then
    printf 'Komplexität: %s Befund(e) — seit 2027-01-01 ein Tor.\n' "$befunde" >&2
    exit 1
fi
printf 'WARN: Komplexität: %s Befund(e) — bis Ende 2026 eine Warnung, ab 2027-01-01 rot. Rückstand mit Termin in docs/status.md.\n' "$befunde" >&2
