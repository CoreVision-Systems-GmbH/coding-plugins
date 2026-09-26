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

# ------------------------------------------------------- Prüfhooks des Repos
# Der Hook-Ordner .githooks reist mit dem Repo, die Einstellung core.hooksPath nicht: In jedem
# frischen Klon fehlt sie, und der pre-commit-Hook (gitleaks) läuft nicht. Deshalb setzt der
# Sessionstart sie, wenn der Ordner da ist und im Repo nichts gesetzt ist — eigene Hooks
# (etwa husky) bleiben unberührt, ebenso Repos ohne .githooks.
hooks_hinweis=""
if [ -f "$proj/.githooks/pre-commit" ] && git -C "$proj" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    top="$(git -C "$proj" rev-parse --show-toplevel 2>/dev/null || true)"
    hier="$(cd "$proj" 2>/dev/null && pwd -P)"
    # Nur an der Wurzel des Repos (im Unterordner eines Monorepos zeigte .githooks ins Leere und
    # schaltete die Hooks des Repos ab), nur für den Vorlagen-Hook (gitleaks) und nur, wenn kein
    # weiterer Hook im Ordner liegt — ein fremdes Repo mit Marker darf beim bloßen Sessionstart
    # keine eigenen Hooks scharf schalten. Beide pwd -P, damit C:/… und /c/… vergleichbar sind.
    if [ -n "$top" ] && [ "$(cd "$top" 2>/dev/null && pwd -P)" = "$hier" ] \
        && grep -q 'gitleaks' "$proj/.githooks/pre-commit" 2>/dev/null \
        && [ "$(ls -A "$proj/.githooks" 2>/dev/null | wc -l)" -eq 1 ]; then
        vorhanden="$(git -C "$proj" config --get core.hooksPath 2>/dev/null || true)"
        if [ -z "$vorhanden" ]; then
            git -C "$proj" config core.hooksPath .githooks 2>/dev/null \
                && hooks_hinweis="core.hooksPath auf .githooks gesetzt — der pre-commit-Hook (gitleaks) läuft ab jetzt in diesem Klon."
        elif [ "$vorhanden" != ".githooks" ] && [ -z "$(git -C "$proj" config --local --get core.hooksPath 2>/dev/null)" ]; then
            # Global gesetzt: nicht verdrängen, aber sagen, dass der Hook des Repos so nicht läuft.
            hooks_hinweis="core.hooksPath ist global auf $vorhanden gesetzt — der pre-commit-Hook des Repos (.githooks) läuft nicht; bei Bedarf: git config core.hooksPath .githooks"
        fi
    fi
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
[ -n "$hooks_hinweis" ] && echo "Hinweis: $hooks_hinweis"
exit 0
