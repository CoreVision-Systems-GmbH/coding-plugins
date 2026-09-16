#!/usr/bin/env bash
# standard-context.sh — SessionStart-Hook (startup, resume, clear, compact).
#
# Aktiviert den Firmenstandard, wenn das Repo ihn erklärt hat:
#   - `coding-standard@corevision` steht in <projekt>/.claude/settings.json, oder
#   - eine Markerdatei <projekt>/.coding-standard existiert.
# Sonst: keine Ausgabe (Vault, Doku-Repos, fremde Projekte bleiben unberührt).
#
# Warum ein Zeiger statt des vollen Textes: Claude Code blendet Hook-Ausgaben über
# rund 2 KB nur als Vorschau ein und lagert den Rest in eine Datei aus. Kern und
# Overlay sind zusammen 10–15 KB. Deshalb gibt der Hook eine kurze, vollständig
# sichtbare Anweisung aus, die Dateien mit dem Read-Tool zu lesen — samt den harten
# Regeln als Kurzform, falls das Lesen ausbleibt.
#
# Notausgang: CODING_STANDARD_OFF=1 in der Umgebung.

set -u

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"

# --stacks: nur die erkannten Stacks ausgeben — ohne Aktivierung, ohne Anweisung. Für
# scripts/projekt-aufnehmen.sh, das ein noch nicht erklärtes Repo einordnen muss; so gibt
# es die Erkennung nur an einer Stelle.
nur_stacks=0
[ "${1:-}" = "--stacks" ] && nur_stacks=1

[ "${CODING_STANDARD_OFF:-0}" = "1" ] && [ "$nur_stacks" -eq 0 ] && exit 0
[ -f "$root/core/kern.md" ] || exit 0

# ------------------------------------------------------------- Aktivierung
aktiv=0
if [ -f "$proj/.claude/settings.json" ] && grep -q 'coding-standard@corevision' "$proj/.claude/settings.json" 2>/dev/null; then
    aktiv=1
fi
[ -f "$proj/.coding-standard" ] && aktiv=1
[ "$aktiv" -eq 1 ] || [ "$nur_stacks" -eq 1 ] || exit 0

# ---------------------------------------------------------- Stack-Erkennung
stacks=""

if [ -f "$proj/composer.json" ] && grep -q '"laravel/framework"' "$proj/composer.json" 2>/dev/null; then
    stacks="$stacks laravel"
fi

fastapi=0
if [ -f "$proj/pyproject.toml" ] && grep -qi 'fastapi' "$proj/pyproject.toml" 2>/dev/null; then
    fastapi=1
else
    for req in "$proj"/requirements*.txt; do
        [ -f "$req" ] && grep -qiE '^fastapi([[:space:]=<>~\[]|$)' "$req" 2>/dev/null && fastapi=1
    done
fi
[ "$fastapi" -eq 1 ] && stacks="$stacks fastapi"

if [ -f "$proj/package.json" ] && grep -q '"next"[[:space:]]*:' "$proj/package.json" 2>/dev/null; then
    stacks="$stacks nextjs"
fi

if [ -f "$proj/package.json" ] && grep -q '"astro"[[:space:]]*:' "$proj/package.json" 2>/dev/null; then
    stacks="$stacks astro"
fi

# WordPress: im Bedrock-Layout als Composer-Paket, im Bestand an der wp-config.php im
# Wurzelverzeichnis.
wordpress=0
if [ -f "$proj/composer.json" ] && grep -qE '"(roots|johnpbloch)/wordpress"' "$proj/composer.json" 2>/dev/null; then
    wordpress=1
fi
[ -f "$proj/wp-config.php" ] && wordpress=1
[ "$wordpress" -eq 1 ] && stacks="$stacks wordpress"

# Stacks ohne eigene Markerdatei (z. B. `script`) nennen sich in .coding-standard
# selbst: eine Zeile `stack: <name>` je Stack.
if [ -f "$proj/.coding-standard" ]; then
    while IFS= read -r zeile || [ -n "$zeile" ]; do
        case "$zeile" in
            stack:*)
                s="$(printf '%s' "${zeile#stack:}" | tr -d '[:space:]')"
                [ -n "$s" ] && stacks="$stacks $s"
                ;;
        esac
    done < "$proj/.coding-standard"
fi

# Doppelte entfernen, Reihenfolge des ersten Auftretens behalten.
eindeutig=""
for s in $stacks; do
    case " $eindeutig " in
        *" $s "*) ;;
        *) eindeutig="$eindeutig $s" ;;
    esac
done
stacks="$eindeutig"

if [ "$nur_stacks" -eq 1 ]; then
    # shellcheck disable=SC2086
    echo $stacks
    exit 0
fi

# ------------------------------------------------------------------ Ausgabe
erkannt="keiner"
dateien="$root/core/kern.md"
fehlend=""
for s in $stacks; do
    if [ -f "$root/stacks/$s.md" ]; then
        dateien="$dateien
$root/stacks/$s.md"
    else
        fehlend="$fehlend $s"
    fi
done
[ -n "$stacks" ] && erkannt="$(echo $stacks)"

cat <<EOF
# Firmenstandard coding-standard@corevision gilt in diesem Repo (Stack erkannt: $erkannt)

Lies vor allem anderen — noch in deiner ersten Antwort — mit dem Read-Tool vollständig:
$dateien
Beides gilt für die gesamte Session; nach einer Kompaktierung erneut lesen. Rangfolge bei
Widerspruch: Anweisung des Nutzers > CLAUDE.md und .claude/rules des Repos > Stack-Overlay > Kern.
Bis dahin die harten Regeln in Kurzform: nie direkt auf main, kein Force-Push, keine Secrets im
Repo; nur Beauftragtes ändern; Beweis statt Behauptung und „nicht geprüft“ benennen; alle Texte
Deutsch mit echten Umlauten; Migrationen additiv, Backup vor Migration; produktionswirksame
Aktionen nur nach Bestätigung.
EOF
[ -n "$fehlend" ] && echo "Hinweis: für$fehlend gibt es noch kein Overlay — es gilt nur der Kern."
exit 0
