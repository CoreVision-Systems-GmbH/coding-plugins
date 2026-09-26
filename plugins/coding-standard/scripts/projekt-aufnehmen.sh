#!/usr/bin/env bash
# projekt-aufnehmen.sh — nimmt ein bestehendes Projekt in den Firmenstandard auf.
#
#     projekt-aufnehmen.sh [--dir <pfad>] [Optionen]            Bestandsaufnahme (ändert nichts)
#     projekt-aufnehmen.sh [--dir <pfad>] --apply [Optionen]    Stufe 0 und 1 anlegen
#
# Gegenstück zu projekt-neu.sh für Repos, die nicht mit /projekt-neu entstanden sind. Es
# baut nichts um: Ohne --apply liest es nur und berichtet; mit --apply legt es
# ausschließlich Dateien an, die fehlen — nie wird eine bestehende überschrieben.
#
# Der Standard ist eine Leiter mit vier Stufen; das Skript erledigt die ersten zwei:
#   0 Erklärung        .claude/settings.json (oder Markerdatei .coding-standard) — ab dann
#                      lädt der SessionStart-Hook Kern und Overlay, Git-Guard und Reviewer
#                      gelten.
#   1 Kontext          die gemeinsamen Dateien aus templates/repo: CLAUDE.md mit den echten
#                      Befehlen des Repos, CHANGES.md, docs/status.md, ADR „Aufnahme in den
#                      Firmenstandard“ mit den Lücken, PR-Vorlage, CODEOWNERS, CI-Durchsicht,
#                      Dependabot, pre-commit-Hook mit gitleaks samt .gitleaks.toml, die
#                      .claude/rules des Stacks.
#   2 Lieferweg        Dockerfile, compose, deploy/, release.yml — wird nur berichtet, mit
#                      der Vorlage als Verweis; das ist Arbeit für einen eigenen PR.
#   3 Betriebsvertrag  Fassung im Produkt, Health, TrustProxies, Prüfbefehle, Datenbank —
#                      wird nur berichtet, je Stack aus dem Overlay abgeleitet.
#
# Deterministisch, fragt nichts nach. Die Stack-Erkennung kommt aus dem SessionStart-Hook
# (standard-context.sh --stacks), damit es sie nur an einer Stelle gibt.

set -euo pipefail

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
vorlagen="$root/templates"

# --------------------------------------------------------------- Hilfsmittel
meldung()  { printf '\n== %s\n' "$1"; }
zeile()    { printf '   %s\n' "$1"; }
abbruch()  { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

hilfe() {
    cat <<'EOF'
projekt-aufnehmen.sh — bestehendes Projekt in den Firmenstandard aufnehmen.

Aufruf:
    projekt-aufnehmen.sh [--dir <pfad>] [Optionen]            Bestandsaufnahme, ändert nichts
    projekt-aufnehmen.sh [--dir <pfad>] --apply [Optionen]    legt Stufe 0 und 1 an

Optionen:
    --dir <pfad>          Wurzelverzeichnis des Repos (Vorgabe: aktuelles Verzeichnis)
    --stack <name>        Stack erzwingen (sonst Erkennung wie im SessionStart-Hook);
                          nötig für Stacks ohne Markerdatei, z. B. script
    --name <kebab>        Projektname (Vorgabe: Repo-Name aus origin, sonst Ordnername)
    --owner <owner>       GitHub-Eigentümer (Vorgabe: aus origin)
    --purpose "<text>"    Zweck in ein bis zwei Sätzen (Vorgabe: erster Absatz der README)
    --customer "<text>"   Kunde und Instanz; ohne Angabe: intern
    --company "<text>"    Rechteinhaber für LICENSE (Vorgabe: CoreVision Systems GmbH)
    --vault <pfad>        Vault, in dem Projektakte und Daily Log fortgeschrieben werden
    --apply               anlegen statt nur berichten; verlangt einen sauberen Arbeitsbaum
    --help                diese Hilfe

Was --apply anlegt: nur Dateien, die fehlen — .claude/settings.json, CLAUDE.md (Befehle aus
composer.json, package.json, Makefile), CHANGES.md, LICENSE, version.txt (aus dem letzten
Tag), .editorconfig, .gitattributes, .github/ (PR-Vorlage, CODEOWNERS, claude-review.yml,
dependabot.yml), .githooks/pre-commit mit .gitleaks.toml (gitleaks vor jedem Commit; setzt
dazu core.hooksPath), docs/status.md und die ADR „Aufnahme in den Firmenstandard“ mit den
Lücken, die .claude/rules des Stacks, bei Stacks ohne Markerdatei .coding-standard.
Nie: Dockerfile, compose, deploy/, release.yml, Code. Das sind Stufe 2 und 3, eigene PRs.
EOF
}

# Platzhalter ersetzen — wie in projekt-neu.sh (reines bash, kein envsubst, kein sed-Maskieren).
ersatz_maskieren() { # <text>
    local t="$1"
    t="${t//\\/\\\\}"
    t="${t//&/\\&}"
    printf '%s' "$t"
}

ersetzen_in_datei() {
    local datei="$1" inhalt schluessel wert
    inhalt="$(cat "$datei")"
    for schluessel in "${!ERSATZ[@]}"; do
        wert="$(ersatz_maskieren "${ERSATZ[$schluessel]}")"
        inhalt="${inhalt//\{\{$schluessel\}\}/$wert}"
    done
    printf '%s\n' "$inhalt" > "$datei"
}

# Setzt alle Schlüssel der stack.conf zurück, auch die hier ungelesenen — sonst bliebe der
# Wert einer vorher gelesenen Vorlage stehen (SC2034).
# shellcheck disable=SC2034
stack_lesen() { # <stack> — setzt LABEL DESCRIPTION REQUIRES CONTAINERIZED MARKER
    LABEL=""; DESCRIPTION=""; REQUIRES=""; DATABASE=""; CONTAINERIZED=0; MARKER=0
    # shellcheck disable=SC1090
    . "$vorlagen/$1/stack.conf"
}

# Namen der Einträge unter "scripts" einer composer.json oder package.json, einer je Zeile.
# Ohne jq: Zeilen der Form  "name": …  innerhalb des scripts-Blocks auf Tiefe 0.
json_scripts() { # <json-datei>
    awk '
        /^[[:space:]]*"scripts"[[:space:]]*:[[:space:]]*\{/ { drin = 1; tiefe = 0; next }
        drin {
            auf = gsub(/\{/, "{"); zu = gsub(/\}/, "}")
            if (tiefe == 0 && match($0, /^[[:space:]]*"[^"]+"[[:space:]]*:/)) {
                s = $0; sub(/^[[:space:]]*"/, "", s); sub(/".*$/, "", s); print s
            }
            tiefe += auf - zu
            if (tiefe < 0) exit
        }' "$1"
}

# Datei vorhanden und Muster darin? — für den Betriebsvertrag.
hat() { # <datei relativ zu DIR> <ERE>
    [ -f "$DIR/$1" ] && grep -qE -- "$2" "$DIR/$1" 2>/dev/null
}

# Betriebsdatenbank des Bestands: postgresql, mariadb, mysql, sqlite, sqlsrv, mongodb oder
# nichts. Das Compose-Abbild ist die Wahrheit im Betrieb und geht vor; .env.example sagt,
# womit die Anwendung spricht (Laravel: DB_CONNECTION, sonst DATABASE_URL). Testdatenbanken
# bleiben außen vor — phpunit.xml ebenso wie Schlüssel mit TEST im Namen (TEST_DATABASE_URL).
datenbank_erkennen() {
    local f bild name
    for f in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
        [ -f "$DIR/$f" ] || continue
        while IFS= read -r bild; do
            # ${DB_IMAGE:-mysql:8.4} → mysql:8.4
            bild="${bild#\$\{*:-}"; bild="${bild%\}}"
            case "$bild" in *mssql/server*) printf sqlsrv; return ;; esac
            name="${bild##*/}"; name="${name%%[:@]*}"
            case "$name" in
                postgres|postgresql|postgis|pgvector|timescaledb*) printf postgresql; return ;;
                mariadb) printf mariadb; return ;;
                mysql|mysql-server) printf mysql; return ;;
                mongo) printf mongodb; return ;;
            esac
        done < <(sed -nE "s/^[[:space:]]*image:[[:space:]]*[\"']?([^\"'[:space:]]+).*/\1/p" "$DIR/$f")
    done
    [ -f "$DIR/.env.example" ] || return 0
    case "$(sed -nE "s/^DB_CONNECTION=[\"']?([a-z]+).*/\1/p" "$DIR/.env.example" | head -n 1)" in
        pgsql)   printf postgresql; return ;;
        mariadb) printf mariadb; return ;;
        mysql)   printf mysql; return ;;
        sqlite)  printf sqlite; return ;;
        sqlsrv)  printf sqlsrv; return ;;
        mongodb) printf mongodb; return ;;
    esac
    case "$(grep -vE '^[A-Z0-9_]*TEST[A-Z0-9_]*=' "$DIR/.env.example" \
            | sed -nE "s/^[A-Z0-9_]*DATABASE_URL=[\"']?([a-z0-9+]+):.*/\1/p" | head -n 1)" in
        postgres|postgresql|postgresql+*) printf postgresql ;;
        mariadb|mariadb+*)                printf mariadb ;;
        mysql|mysql+*)                    printf mysql ;;
        sqlite|sqlite+*)                  printf sqlite ;;
        mongodb|mongodb+*)                printf mongodb ;;
    esac
}

datenbank_name() { # <kennung>
    case "$1" in
        postgresql) printf PostgreSQL ;; mariadb) printf MariaDB ;; mysql) printf MySQL ;;
        sqlite) printf SQLite ;; sqlsrv) printf 'SQL Server' ;; mongodb) printf MongoDB ;;
        *) printf '%s' "$1" ;;
    esac
}

# Erste ADR des Projekts, deren Titel die Datenbank nennt — eine beiläufige Erwähnung im Text
# („weg von MySQL“) begründet keine Abweichung. Die ADR der Aufnahme und die Vorlage zählen nicht.
datenbank_adr() { # <anzeigename>
    local adr titel
    for adr in "$DIR"/docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
        [ -f "$adr" ] || continue
        case "$adr" in *aufnahme-firmenstandard.md|*/0000-*) continue ;; esac
        titel="$(grep -m 1 '^# ' "$adr" || true)"
        if printf '%s' "$titel" | grep -qiw -- "$1"; then
            printf '%s' "${adr#"$DIR"/}"; return
        fi
    done
}

# Ein Prüfpunkt der Bestandsaufnahme. Fehlendes aus Stufe 2 und 3 wandert in LUECKEN
# (Markdown-Liste für ADR und status.md) — Stufe 0 und 1 legt --apply selbst an.
LUECKEN=""
declare -A N_OK=() N_FEHLT=()
pruefe() { # <stufe> <0=ok|1=fehlt> <beschreibung> [verweis]
    local stufe="$1" status="$2" text="$3" verweis="${4:-}"
    if [ "$status" -eq 0 ]; then
        printf '   ok      %s\n' "$text"
        N_OK[$stufe]=$(( ${N_OK[$stufe]:-0} + 1 ))
    else
        printf '   fehlt   %s%s\n' "$text" "${verweis:+  ← $verweis}"
        N_FEHLT[$stufe]=$(( ${N_FEHLT[$stufe]:-0} + 1 ))
        case "$stufe" in
            2|3) LUECKEN="$LUECKEN
- Stufe $stufe: $text${verweis:+ (Vorlage: \`$verweis\`)}" ;;
        esac
    fi
}

# ----------------------------------------------------------------- Argumente
DIR=""; STACK_ARG=""; NAME_ARG=""; OWNER_ARG=""; PURPOSE_ARG=""
CUSTOMER="intern"
COMPANY="CoreVision Systems GmbH"
VAULT=""
APPLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)       DIR="${2:?--dir braucht einen Wert}"; shift 2 ;;
        --stack)     STACK_ARG="${2:?--stack braucht einen Wert}"; shift 2 ;;
        --name)      NAME_ARG="${2:?--name braucht einen Wert}"; shift 2 ;;
        --owner)     OWNER_ARG="${2:?--owner braucht einen Wert}"; shift 2 ;;
        --purpose)   PURPOSE_ARG="${2:?--purpose braucht einen Wert}"; shift 2 ;;
        --customer)  CUSTOMER="${2:?--customer braucht einen Wert}"; shift 2 ;;
        --company)   COMPANY="${2:?--company braucht einen Wert}"; shift 2 ;;
        --vault)     VAULT="${2:?--vault braucht einen Wert}"; shift 2 ;;
        --apply)     APPLY=1; shift ;;
        --help|-h)   hilfe; exit 0 ;;
        *)           abbruch "Unbekannte Option: $1 (siehe --help)" ;;
    esac
done

# ------------------------------------------------------------------- Repo
[ -n "$DIR" ] || DIR="$PWD"
case "$DIR" in
    /*|[A-Za-z]:*) ;;
    *) DIR="$(pwd)/$DIR" ;;
esac
[ -d "$DIR" ] || abbruch "'$DIR' ist kein Verzeichnis."
DIR="$(cd "$DIR" && pwd)"

wurzel="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$wurzel" ] || abbruch "'$DIR' liegt in keinem Git-Repository. Die Aufnahme setzt ein Repo voraus (git init -b main, ein Commit)."
# -ef statt Textvergleich: Unter Windows heißt derselbe Ordner mal /tmp/…, mal C:/…/Temp/….
[ "$DIR" -ef "$wurzel" ] \
    || abbruch "'$DIR' ist nicht das Wurzelverzeichnis des Repos ($wurzel). Bitte dieses angeben."

zweig="$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
aenderungen="$(git -C "$DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

REMOTE="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
REMOTE_OWNER=""; REMOTE_NAME=""
if [ -n "$REMOTE" ]; then
    r="${REMOTE%.git}"; r="${r%/}"
    REMOTE_NAME="${r##*/}"
    r="${r%/*}"
    REMOTE_OWNER="${r##*[/:]}"
fi

NAME="${NAME_ARG:-${REMOTE_NAME:-$(basename "$DIR")}}"
OWNER="${OWNER_ARG:-$REMOTE_OWNER}"

printf '%s' "$NAME" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || zeile "Hinweis: Name '$NAME' ist nicht kebab-case — für Abbild und Container-Namen später anpassen (--name)."

# ------------------------------------------------------------- Stack
erkannt="$(cd "$DIR" && env CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$DIR" \
    bash "$root/hooks/standard-context.sh" --stacks 2>/dev/null || true)"

STACK=""; STACK_QUELLE=""
if [ -n "$STACK_ARG" ]; then
    [ -f "$vorlagen/$STACK_ARG/stack.conf" ] \
        || abbruch "Unbekannter Stack '$STACK_ARG'. Verfügbar: $(
            for k in "$vorlagen"/*/stack.conf; do
                n="$(basename "$(dirname "$k")")"; case "$n" in _*) continue ;; esac; printf '%s ' "$n"
            done)"
    STACK="$STACK_ARG"; STACK_QUELLE="aus --stack"
else
    for s in $erkannt; do
        if [ -f "$vorlagen/$s/stack.conf" ]; then STACK="$s"; STACK_QUELLE="erkannt"; break; fi
    done
fi

AUSNAHME=""
case " $erkannt " in *" nextjs "*) AUSNAHME="nextjs" ;; esac

if [ -n "$STACK" ]; then
    stack_lesen "$STACK"
else
    LABEL="kein Stack-Overlay, nur Kern"; DATABASE=""; CONTAINERIZED=0; MARKER=0
fi

# --------------------------------------------------------------- Zweck
PURPOSE="$PURPOSE_ARG"
if [ -z "$PURPOSE" ] && [ -f "$DIR/README.md" ]; then
    PURPOSE="$(grep -vE '^[[:space:]]*($|#|>|\||-|\*|<!--|\[|!\[|```)' "$DIR/README.md" | head -n 1 | cut -c1-300 | sed 's/[[:space:]]*$//')"
fi
[ -n "$PURPOSE" ] || PURPOSE="Zweck noch eintragen (die README hatte keinen Absatz dafür)."

# ------------------------------------------------------- Erklärung (Stufe 0)
erklaert_settings=0; erklaert_marker=0
[ -f "$DIR/.claude/settings.json" ] && grep -q 'coding-standard@corevision' "$DIR/.claude/settings.json" 2>/dev/null && erklaert_settings=1
[ -f "$DIR/.coding-standard" ] && erklaert_marker=1

# =============================================================== Bericht
meldung "Bestandsaufnahme: $NAME"
zeile "Ordner:   $DIR"
zeile "Remote:   ${REMOTE:-keines}"
zeile "Zweig:    $zweig, $([ "$aenderungen" = "0" ] && echo 'Arbeitsbaum sauber' || echo "$aenderungen Änderung(en) im Arbeitsbaum")"
if [ -n "$STACK" ]; then
    zeile "Stack:    $STACK ($LABEL) — $STACK_QUELLE; Overlay stacks/$STACK.md"
else
    zeile "Stack:    keiner erkannt — es gilt nur der Kern (Stack ohne Markerdatei: --stack <name>)"
fi
[ -z "$AUSNAHME" ] || zeile "Hinweis:  Next.js erkannt — Ausnahme mit Auflagen (stacks/nextjs.md), kein Register für die Aufnahme"
if [ "$erklaert_settings" -eq 1 ]; then
    zeile "Erklärt:  ja — .claude/settings.json"
elif [ "$erklaert_marker" -eq 1 ]; then
    zeile "Erklärt:  ja — Markerdatei .coding-standard (wirkt nur bei Codern, die das Plugin schon haben)"
else
    zeile "Erklärt:  nein"
fi

meldung "Stufe 0 — Erklärung"
pruefe 0 "$([ "$erklaert_settings" -eq 1 ] && echo 0 || echo 1)" \
    ".claude/settings.json erklärt coding-standard@corevision (installiert das Plugin für jeden, der das Repo öffnet)" \
    "templates/repo/.claude/settings.json"
if [ -n "$STACK" ] && [ "$MARKER" = "1" ]; then
    pruefe 0 "$([ "$erklaert_marker" -eq 1 ] && grep -q "stack: $STACK" "$DIR/.coding-standard" 2>/dev/null && echo 0 || echo 1)" \
        ".coding-standard nennt den Stack ($STACK hat keine Markerdatei)"
fi

meldung "Stufe 1 — Kontext (gemeinsame Dateien aus templates/repo)"
# Die Erlaubnis- und Sperrliste der Sessions steht in derselben Datei wie die Erklärung;
# eine ältere settings.json hat sie nicht, wird aber nicht überschrieben — deshalb eigene
# Zeile, und der Punkt wandert trotz Stufe 1 in die Lückenliste (ADR, status.md): --apply
# kann ihn nicht schließen, jemand muss die Liste von Hand übernehmen.
if [ -f "$DIR/.claude/settings.json" ]; then
    if grep -q '"permissions"' "$DIR/.claude/settings.json"; then
        pruefe 1 0 ".claude/settings.json: permissions (Erlaubnis- und Sperrliste für Sessions — .env, Tresor, Datenbanklöscher)"
    else
        pruefe 1 1 ".claude/settings.json: permissions (Erlaubnis- und Sperrliste für Sessions — .env, Tresor, Datenbanklöscher)" \
            "templates/repo/.claude/settings.json"
        LUECKEN="$LUECKEN
- Stufe 1: .claude/settings.json ohne \`permissions\` — Erlaubnis- und Sperrliste aus \`templates/repo/.claude/settings.json\` von Hand übernehmen (die Datei wird nicht überschrieben)"
    fi
fi
while IFS= read -r rel; do
    case "$rel" in
        docs/decisions/0001-projektstart.md) continue ;;   # für Bestand: ADR „Aufnahme“
        docs/status.md) continue ;;                        # kommt aus templates/aufnahme
        .claude/settings.json) continue ;;                 # Stufe 0
    esac
    pruefe 1 "$([ -e "$DIR/$rel" ] && echo 0 || echo 1)" "$rel" "templates/repo/$rel"
done < <(cd "$vorlagen/repo" && find . -type f | sed 's#^\./##' | sort)
pruefe 1 "$([ -f "$DIR/docs/status.md" ] && echo 0 || echo 1)" "docs/status.md" "templates/aufnahme/status.md"
adr_vorhanden="$(ls "$DIR"/docs/decisions/*aufnahme-firmenstandard.md 2>/dev/null | head -n 1 || true)"
pruefe 1 "$([ -n "$adr_vorhanden" ] && echo 0 || echo 1)" "docs/decisions/NNNN-aufnahme-firmenstandard.md (ADR mit den Lücken)" "templates/aufnahme/adr-aufnahme.md"
if [ -n "$STACK" ] && [ -d "$vorlagen/$STACK/dateien/.claude/rules" ]; then
    for regel in "$vorlagen/$STACK/dateien/.claude/rules"/*.md; do
        [ -f "$regel" ] || continue
        rel=".claude/rules/$(basename "$regel")"
        pruefe 1 "$([ -f "$DIR/$rel" ] && echo 0 || echo 1)" "$rel (Regeln des Stacks)" "templates/$STACK/dateien/$rel"
    done
fi
# Editor-Dateien des Stacks: Tore als Aufgaben, Git-Schutz und Erweiterungen — derselbe Schutz
# für den Menschen im Editor wie für Claude (Git-Guard). Nie überschrieben, nur ergänzt.
if [ -n "$STACK" ] && [ -d "$vorlagen/$STACK/dateien/.vscode" ]; then
    for editor in "$vorlagen/$STACK/dateien/.vscode"/*.json; do
        [ -f "$editor" ] || continue
        rel=".vscode/$(basename "$editor")"
        pruefe 1 "$([ -f "$DIR/$rel" ] && echo 0 || echo 1)" "$rel (Editor: Tore als Aufgaben, Git-Schutz, Erweiterungen)" "templates/$STACK/dateien/$rel"
    done
fi
# Dependabot ist Konfiguration, kein Lieferweg — je Stack passend, deshalb aus dessen Vorlage.
dependabot_vorlage=""
[ -n "$STACK" ] && [ -f "$vorlagen/$STACK/dateien/.github/dependabot.yml" ] && dependabot_vorlage="templates/$STACK/dateien/.github/dependabot.yml"
pruefe 1 "$([ -f "$DIR/.github/dependabot.yml" ] && echo 0 || echo 1)" ".github/dependabot.yml" "$dependabot_vorlage"
if [ -f "$DIR/CHANGES.md" ]; then
    pruefe 1 "$(grep -qE '^## (Unveröffentlicht|\[?Unreleased\]?)' "$DIR/CHANGES.md" && echo 0 || echo 1)" \
        "CHANGES.md hat einen Abschnitt „Unveröffentlicht“ (Keep a Changelog)"
fi
if [ -f "$DIR/CLAUDE.md" ]; then
    pruefe 1 "$(grep -qE '^## Befehle' "$DIR/CLAUDE.md" && echo 0 || echo 1)" \
        "CLAUDE.md hat einen Abschnitt „Befehle“ (Claude übernimmt sie von dort, erfindet keine)"
fi
letzter_tag="$(git -C "$DIR" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
if [ -f "$DIR/version.txt" ] && [ -n "$letzter_tag" ]; then
    pruefe 1 "$([ "$(tr -d '[:space:]' < "$DIR/version.txt")" = "${letzter_tag#v}" ] && echo 0 || echo 1)" \
        "version.txt entspricht dem letzten Tag ($letzter_tag)"
fi

meldung "Stufe 2 — Lieferweg$([ "$CONTAINERIZED" = "1" ] && echo ' (Abbild aus dem Tag, Ausrollen per deploy/)' || echo ' (CI und Release)')"
lieferweg=".github/workflows/tests.yml"
if [ "$CONTAINERIZED" = "1" ]; then
    lieferweg="$lieferweg Dockerfile compose.yaml compose.build.yaml .env.example deploy/install.sh deploy/update.sh deploy/backup.sh deploy/smoke.sh deploy/smoke.txt scripts/release-notes.sh scripts/konfig-pruefen.sh scripts/lizenzen-pruefen.sh .github/workflows/release.yml"
fi
for rel in $lieferweg; do
    verweis=""
    [ -n "$STACK" ] && [ -f "$vorlagen/$STACK/dateien/$rel" ] && verweis="templates/$STACK/dateien/$rel"
    [ -z "$verweis" ] && [ -f "$vorlagen/repo/$rel" ] && verweis="templates/repo/$rel"
    pruefe 2 "$([ -e "$DIR/$rel" ] && echo 0 || echo 1)" "$rel" "$verweis"
done
if [ -f "$DIR/.github/workflows/tests.yml" ]; then
    pruefe 2 "$(grep -qE '^[[:space:]]+ci:[[:space:]]*$' "$DIR/.github/workflows/tests.yml" && echo 0 || echo 1)" \
        "tests.yml: Auftrag heißt „ci“ (Pflicht-Check des Rulesets)"
    case "$STACK" in laravel|fastapi)
        pruefe 2 "$(grep -q 'diff-cover' "$DIR/.github/workflows/tests.yml" && echo 0 || echo 1)" \
            "tests.yml: Schritt „Diff-Abdeckung“ (diff-cover, 80 % der geänderten Zeilen)" "templates/$STACK/dateien/.github/workflows/tests.yml"
        pruefe 2 "$([ -f "$DIR/.github/workflows/nightly.yml" ] && echo 0 || echo 1)" \
            "nightly.yml: Mutationstest (Laravel: dazu Suite gegen die Betriebs-Datenbank)" "templates/$STACK/dateien/.github/workflows/nightly.yml"
        ;;
    esac

    pruefe 2 "$(grep -q 'pr-text-pruefen' "$DIR/.github/workflows/tests.yml" && echo 0 || echo 1)" \
        "tests.yml: Schritt „PR-Text prüfen“ (scripts/pr-text-pruefen.sh)" "${STACK:+templates/$STACK/dateien/.github/workflows/tests.yml}"
fi

meldung "Stufe 3 — Betriebsvertrag$([ -n "$STACK" ] && echo " (stacks/$STACK.md, Abschnitt 4)" || echo ' (ohne Stack: nur Kern)')"
case "$STACK" in
    laravel)
        pruefe 3 "$(hat config/app.php "'version'" && echo 0 || echo 1)" "Fassung im Produkt: config/app.php liest APP_IMAGE_VERSION ('version')"
        pruefe 3 "$(hat bootstrap/app.php 'trustProxies' && echo 0 || echo 1)" "TrustProxies hinter dem Edge-Caddy (bootstrap/app.php)"
        for s in check ci:setup ci:check lint lint:check types:check test; do
            pruefe 3 "$(hat composer.json "\"$s\"[[:space:]]*:" && echo 0 || echo 1)" "composer.json: Script „$s“"
        done
        pruefe 3 "$([ -f "$DIR/phpstan.neon" ] && echo 0 || echo 1)" "Larastan (phpstan.neon; Bestand Stufe 7, neu Stufe 8)"
        pruefe 3 "$(hat pint.json 'declare_strict_types' && echo 0 || echo 1)" "pint.json: declare_strict_types und Imports" "templates/laravel/dateien/pint.json"
        pruefe 3 "$([ -f "$DIR/phpmd.xml" ] && [ -f "$DIR/scripts/komplexitaet-pruefen.sh" ] && echo 0 || echo 1)" "Kennzahlen je Funktion (phpmd.xml, scripts/komplexitaet-pruefen.sh)" "templates/laravel/dateien/phpmd.xml"
        pruefe 3 "$([ -f "$DIR/tests/Feature/AppVersionTest.php" ] && echo 0 || echo 1)" "AppVersionTest: Fassung auf beiden Oberflächen sichtbar"
        pruefe 3 "$(hat .env.example '^APP_VERSION=' && echo 0 || echo 1)" ".env.example: APP_VERSION (Image-Tag der Instanz)"
        pruefe 3 "$(hat .env.example '^APP_TIMEZONE=' && echo 0 || echo 1)" ".env.example: APP_TIMEZONE (nie hart UTC)"
        pruefe 3 "$(hat compose.yaml '/up' && echo 0 || echo 1)" "compose.yaml: Healthcheck auf /up"
        pruefe 3 "$(hat compose.yaml 'read_only' && hat compose.yaml 'cap_drop' && hat compose.yaml 'no-new-privileges' && hat compose.yaml 'max-size' && echo 0 || echo 1)" "compose.yaml: Härtung (read_only, cap_drop, no-new-privileges, Log-Rotation)" "templates/$STACK/dateien/compose.yaml"
        ;;
    fastapi)
        pruefe 3 "$([ -f "$DIR/app/settings.py" ] && echo 0 || echo 1)" "Konfiguration an einer Stelle (app/settings.py)"
        pruefe 3 "$(grep -rqs 'healthz' "$DIR/app" && echo 0 || echo 1)" "GET /healthz mit Fassung"
        pruefe 3 "$(hat Dockerfile 'proxy-headers' && echo 0 || echo 1)" "Uvicorn mit --proxy-headers hinter dem Edge-Caddy (Dockerfile)"
        pruefe 3 "$( { hat pyproject.toml 'ruff' || hat requirements-dev.txt 'ruff'; } && echo 0 || echo 1)" "ruff (Format und Lint)"
        pruefe 3 "$([ -f "$DIR/scripts/komplexitaet-pruefen.sh" ] && echo 0 || echo 1)" "Kennzahlen je Funktion (scripts/komplexitaet-pruefen.sh, ruff C901/PLR0912/PLR0915)" "templates/fastapi/dateien/scripts/komplexitaet-pruefen.sh"
        pruefe 3 "$([ -f "$DIR/scripts/check.sh" ] && echo 0 || echo 1)" "Ein Prüfbefehl für alles (scripts/check.sh)" "templates/fastapi/dateien/scripts/check.sh"
        pruefe 3 "$(hat .env.example '^APP_VERSION=' && echo 0 || echo 1)" ".env.example: APP_VERSION (Image-Tag der Instanz)"
        pruefe 3 "$(hat compose.yaml '/healthz' && echo 0 || echo 1)" "compose.yaml: Healthcheck auf /healthz"
        pruefe 3 "$(hat compose.yaml 'read_only' && hat compose.yaml 'cap_drop' && hat compose.yaml 'no-new-privileges' && hat compose.yaml 'max-size' && echo 0 || echo 1)" "compose.yaml: Härtung (read_only, cap_drop, no-new-privileges, Log-Rotation)" "templates/$STACK/dateien/compose.yaml"
        ;;
    astro)
        pruefe 3 "$(hat astro.config.mjs 'site:' && echo 0 || echo 1)" "astro.config.mjs: site gesetzt (Canonical, Sitemap)"
        pruefe 3 "$( { [ -f "$DIR/astro.config.mjs" ] && ! grep -q '\.invalid' "$DIR/astro.config.mjs"; } && echo 0 || echo 1)" "astro.config.mjs: site zeigt nicht auf eine Platzhalter-Domain"
        # check:types belegt, dass `check` mehr ist als der reine Typcheck (Typen, Bau, Tests).
        for s in check check:types build test; do
            pruefe 3 "$(hat package.json "\"$s\"[[:space:]]*:" && echo 0 || echo 1)" "package.json: Script „$s“"
        done
        pruefe 3 "$([ -d "$DIR/tests" ] && echo 0 || echo 1)" "tests/ gegen dist/"
        pruefe 3 "$(hat docker/Caddyfile '/healthz' && echo 0 || echo 1)" "Caddyfile: /healthz mit Fassung"
        pruefe 3 "$(hat compose.yaml 'read_only' && hat compose.yaml 'cap_drop' && hat compose.yaml 'no-new-privileges' && hat compose.yaml 'max-size' && echo 0 || echo 1)" "compose.yaml: Härtung (read_only, cap_drop, no-new-privileges, Log-Rotation)" "templates/$STACK/dateien/compose.yaml"
        ;;
    wordpress)
        pruefe 3 "$([ -f "$DIR/config/application.php" ] && echo 0 || echo 1)" "Konfiguration aus ENV (config/application.php, Bedrock-Layout)"
        pruefe 3 "$(hat config/application.php 'DISALLOW_FILE_MODS' && echo 0 || echo 1)" "Kein Code aus dem Admin (DISALLOW_FILE_MODS)"
        pruefe 3 "$([ -f "$DIR/web/app/mu-plugins/firmenstandard.php" ] && echo 0 || echo 1)" "Mu-Plugin firmenstandard (/healthz, Fassung, Härtung)"
        pruefe 3 "$([ -f "$DIR/wp-cli.yml" ] && echo 0 || echo 1)" "wp-cli.yml (path: web/wp)"
        pruefe 3 "$([ -f "$DIR/phpcs.xml" ] && echo 0 || echo 1)" "PHPCS mit WordPress-Coding-Standards (phpcs.xml)"
        pruefe 3 "$([ -f "$DIR/phpstan.neon" ] && echo 0 || echo 1)" "PHPStan mit WordPress-Stubs (phpstan.neon)"
        pruefe 3 "$([ -f "$DIR/phpmd.xml" ] && [ -f "$DIR/scripts/komplexitaet-pruefen.sh" ] && echo 0 || echo 1)" "Kennzahlen je Funktion (phpmd.xml, scripts/komplexitaet-pruefen.sh)" "templates/wordpress/dateien/phpmd.xml"
        for s in lint analyse test check; do
            pruefe 3 "$(hat composer.json "\"$s\"[[:space:]]*:" && echo 0 || echo 1)" "composer.json: Script „$s“"
        done
        pruefe 3 "$(hat compose.yaml '/healthz' && echo 0 || echo 1)" "compose.yaml: Healthcheck auf /healthz"
        pruefe 3 "$(hat compose.yaml 'read_only' && hat compose.yaml 'cap_drop' && hat compose.yaml 'no-new-privileges' && hat compose.yaml 'max-size' && echo 0 || echo 1)" "compose.yaml: Härtung (read_only, cap_drop, no-new-privileges, Log-Rotation)" "templates/$STACK/dateien/compose.yaml"
        ;;
    script)
        pruefe 3 "$([ -n "$(ls "$DIR"/scripts/*.sh "$DIR"/scripts/*.py "$DIR"/scripts/*.ps1 2>/dev/null)" ] && echo 0 || echo 1)" "Werkzeuge unter scripts/ (ein Skript, eine Aufgabe, --help und --dry-run)"
        pruefe 3 "$([ -d "$DIR/tests" ] && [ -n "$(ls -A "$DIR/tests" 2>/dev/null)" ] && echo 0 || echo 1)" "tests/ mit mindestens einer Prüfung"
        pruefe 3 "$([ -f "$DIR/scripts/komplexitaet-pruefen.sh" ] && echo 0 || echo 1)" "Kennzahlen je Funktion (scripts/komplexitaet-pruefen.sh)" "templates/script/dateien/scripts/komplexitaet-pruefen.sh"
        pruefe 3 "$([ -f "$DIR/scripts/check.sh" ] && echo 0 || echo 1)" "Ein Prüfbefehl für alles (scripts/check.sh)" "templates/script/dateien/scripts/check.sh"
        ;;
    "")
        zeile "kein Stack — Betriebsvertrag nicht prüfbar; Kern-Regeln gelten trotzdem"
        ;;
esac
# Datenbank (Kern, „Umsetzen“): PostgreSQL, einzige Ausnahme MariaDB für WordPress, SQLite nur
# in Skripten ohne Dienst. Begründet ist eine Abweichung, wenn eine ADR des Projekts die
# Datenbank im Titel nennt — die ADR der Aufnahme zählt nicht, sie listet sie nur als Lücke.
DB_IST="$(datenbank_erkennen)"
case "$STACK" in wordpress) db_soll=mariadb ;; *) db_soll=postgresql ;; esac
DB_ABWEICHUNG=""
if [ -n "$DB_IST" ]; then
    db_ist_name="$(datenbank_name "$DB_IST")"; db_soll_name="$(datenbank_name "$db_soll")"
    if [ "$DB_IST" = "$db_soll" ] || { [ "$STACK" = script ] && [ "$DB_IST" = sqlite ]; }; then
        pruefe 3 0 "Datenbank: $db_ist_name (Standard)"
    else
        db_adr="$(datenbank_adr "$db_ist_name")"
        if [ -n "$db_adr" ]; then
            DB_ABWEICHUNG="begründet in $db_adr"
            pruefe 3 0 "Datenbank: $db_ist_name statt $db_soll_name — Abweichung $DB_ABWEICHUNG"
        else
            DB_ABWEICHUNG="ADR fehlt"
            pruefe 3 1 "Datenbank: $db_ist_name statt $db_soll_name — Abweichung in einer ADR begründen, Wechsel beim nächsten größeren Umbau"
        fi
    fi
fi
[ -z "$AUSNAHME" ] || zeile "Next.js: Auflagen aus stacks/nextjs.md von Hand prüfen (standalone, eine Instanz, Proxy ohne Puffer, Laravel als Identitätsquelle)"

meldung "Zusammenfassung"
for st in 0 1 2 3; do
    case "$st" in 0) n="Erklärung";; 1) n="Kontext";; 2) n="Lieferweg";; 3) n="Betriebsvertrag";; esac
    printf '   Stufe %s %-16s %s ok, %s fehlt\n' "$st" "$n:" "${N_OK[$st]:-0}" "${N_FEHLT[$st]:-0}"
done

if [ "$APPLY" -eq 0 ]; then
    cat <<EOF

   Ohne --apply wurde nichts geändert. Mit --apply legt das Skript Stufe 0 und 1 an — nur
   Dateien, die fehlen, nie wird eine überschrieben. Stufe 2 und 3 sind eigene PRs; die
   Vorlagen stehen hinter „←“, die Regeln im Overlay.
EOF
    exit 0
fi

# =============================================================== Anlegen
meldung "Anlegen (Stufe 0 und 1)"

[ "$aenderungen" = "0" ] \
    || abbruch "Der Arbeitsbaum ist nicht sauber ($aenderungen Änderungen). Die Aufnahme soll ein eigener, lesbarer Diff sein — erst committen oder stashen."
[ -n "$OWNER" ] || abbruch "Kein Eigentümer: origin fehlt oder ist kein GitHub-Remote. --owner <owner> angeben."

OWNER_LC="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
NAME_SNAKE="$(printf '%s' "$NAME" | tr '-' '_')"
ENV_PREFIX="$(printf '%s' "${NAME##*-}" | tr '[:lower:]' '[:upper:]')_"
IMAGE="ghcr.io/$OWNER_LC/$NAME"
DATUM="$(date +%Y-%m-%d)"
JAHR="$(date +%Y)"

konto=""
if command -v gh >/dev/null 2>&1; then
    konto="$(gh api user --jq '.login' 2>/dev/null || true)"
elif [ -x "/c/Program Files/GitHub CLI/gh.exe" ]; then
    konto="$("/c/Program Files/GitHub CLI/gh.exe" api user --jq '.login' 2>/dev/null || true)"
fi

# Befehle aus dem Repo — nie erfinden. Zweck-Spalte füllt Claude in der Nacharbeit.
befehle_aus_repo() {
    local zeilen="" s t
    if [ -f "$DIR/composer.json" ]; then
        for s in $(json_scripts "$DIR/composer.json"); do
            case "$s" in post-*|pre-*) continue ;; esac
            zeilen="$zeilen
| composer $s | \`composer $s\` |"
        done
    fi
    if [ -f "$DIR/package.json" ]; then
        for s in $(json_scripts "$DIR/package.json"); do
            zeilen="$zeilen
| npm run $s | \`npm run $s\` |"
        done
    fi
    if [ -f "$DIR/Makefile" ]; then
        for t in $(grep -oE '^[a-zA-Z_][a-zA-Z0-9_-]*:' "$DIR/Makefile" | tr -d ':' | sort -u); do
            zeilen="$zeilen
| make $t | \`make $t\` |"
        done
    fi
    if [ -z "$zeilen" ]; then
        printf '%s' '<!-- Befehle des Projekts eintragen — aus README, Makefile oder Werkzeugkonfiguration; nichts erfinden. -->'
        return
    fi
    printf '| Zweck | Befehl |\n| ----- | ------ |%s\n\n<!-- Von /projekt-aufnehmen aus composer.json, package.json und Makefile übernommen.\n     Zweck-Spalte in Worten ausfüllen, Unwichtiges streichen — nichts erfinden. -->' "$zeilen"
}

# Nächste freie ADR-Nummer.
adr_nummer() {
    local hoechste
    hoechste="$(ls "$DIR"/docs/decisions/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null \
        | sed -E 's#.*/([0-9]{4})-.*#\1#' | sort -n | tail -n 1 || true)"
    printf '%04d' $(( 10#${hoechste:-0} + 1 ))
}

[ -n "$LUECKEN" ] || LUECKEN="
- keine — alles vorhanden."

ADR_NR="$(adr_nummer)"

# Die CLAUDE.md nennt die Datenbank, die der Bestand hat — nicht die der Vorlage; Claude
# übernimmt sie von dort (Kern) und soll nicht gegen PostgreSQL schreiben, wo MySQL läuft.
if [ -n "$DB_ABWEICHUNG" ]; then
    DATABASE="$(datenbank_name "$DB_IST") — Abweichung vom Standard ($(datenbank_name "$db_soll")), $DB_ABWEICHUNG"
elif [ -n "$DB_IST" ]; then
    # Gleiche Datenbank wie die Vorlage: deren Wert samt Fassung behalten („PostgreSQL 18“).
    case "$DATABASE" in
        "$(datenbank_name "$DB_IST")"*) ;;
        *) DATABASE="$(datenbank_name "$DB_IST")" ;;
    esac
fi

declare -A ERSATZ=(
    [NAME]="$NAME"
    [NAME_SNAKE]="$NAME_SNAKE"
    [PURPOSE]="$PURPOSE"
    [STACK]="${STACK:-kein}"
    [STACK_LABEL]="$LABEL"
    # Zieldatenbank aus stack.conf; ohne erkannten Stack trägt der Mensch sie ein.
    [DATABASE]="${DATABASE:-unbekannt — in CLAUDE.md eintragen}"
    [OWNER]="$OWNER"
    [OWNER_LC]="$OWNER_LC"
    [OWNER_USER]="${konto:-$OWNER}"
    [COMPANY]="$COMPANY"
    [CUSTOMER]="$CUSTOMER"
    [IMAGE]="$IMAGE"
    [ENV_PREFIX]="$ENV_PREFIX"
    [DATE]="$DATUM"
    [YEAR]="$JAHR"
    [COMMANDS]="$(befehle_aus_repo)"
    [LUECKEN]="$LUECKEN"
    [ADR_NR]="$ADR_NR"
)

liste="$(mktemp)"
trap 'rm -f "$liste"' EXIT
angelegt=0

anlegen() { # <quelle> <ziel relativ zu DIR>
    [ -e "$DIR/$2" ] && return 0
    mkdir -p "$(dirname "$DIR/$2")"
    cp "$1" "$DIR/$2"
    printf '%s\n' "$DIR/$2" >> "$liste"
    zeile "angelegt: $2"
    angelegt=$((angelegt + 1))
}

# Stufe 0
anlegen "$vorlagen/repo/.claude/settings.json" ".claude/settings.json"
if [ -n "$STACK" ] && [ "$MARKER" = "1" ] && [ ! -f "$DIR/.coding-standard" ]; then
    printf 'stack: %s\n' "$STACK" > "$DIR/.coding-standard"
    zeile "angelegt: .coding-standard (stack: $STACK)"
    angelegt=$((angelegt + 1))
fi

# Stufe 1 — gemeinsame Dateien, ohne Projektstart-ADR und ohne den Neuprojekt-Status
while IFS= read -r rel; do
    case "$rel" in
        docs/decisions/0001-projektstart.md|docs/status.md|.claude/settings.json) continue ;;
        version.txt) continue ;;   # kommt aus dem letzten Tag, siehe unten
    esac
    anlegen "$vorlagen/repo/$rel" "$rel"
done < <(cd "$vorlagen/repo" && find . -type f | sed 's#^\./##' | sort)
anlegen "$vorlagen/aufnahme/status.md" "docs/status.md"
if [ -z "$adr_vorhanden" ]; then
    anlegen "$vorlagen/aufnahme/adr-aufnahme.md" "docs/decisions/$ADR_NR-aufnahme-firmenstandard.md"
fi
if [ -n "$STACK" ] && [ -d "$vorlagen/$STACK/dateien/.claude/rules" ]; then
    for regel in "$vorlagen/$STACK/dateien/.claude/rules"/*.md; do
        [ -f "$regel" ] || continue
        anlegen "$regel" ".claude/rules/$(basename "$regel")"
    done
fi
if [ -n "$STACK" ] && [ -d "$vorlagen/$STACK/dateien/.vscode" ]; then
    for editor in "$vorlagen/$STACK/dateien/.vscode"/*.json; do
        [ -f "$editor" ] || continue
        anlegen "$editor" ".vscode/$(basename "$editor")"
    done
fi
[ -z "$dependabot_vorlage" ] || anlegen "$root/$dependabot_vorlage" ".github/dependabot.yml"

# version.txt: aus dem letzten Tag, sonst wie ein neues Projekt.
if [ ! -f "$DIR/version.txt" ]; then
    printf '%s\n' "${letzter_tag#v}" | sed 's/^$/0.1.0/' > "$DIR/version.txt"
    zeile "angelegt: version.txt ($(cat "$DIR/version.txt")$([ -n "$letzter_tag" ] && echo ", aus Tag $letzter_tag"))"
    angelegt=$((angelegt + 1))
fi

# Platzhalter nur in den eben angelegten Dateien ersetzen und auf Reste prüfen.
sort -u "$liste" -o "$liste"
while IFS= read -r datei; do
    [ -f "$datei" ] && ersetzen_in_datei "$datei"
done < "$liste"
rest=""
while IFS= read -r datei; do
    [ -f "$datei" ] && grep -qE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$datei" && rest="$rest
  $datei"
done < "$liste"
[ -z "$rest" ] || abbruch "Unersetzte Platzhalter in:$rest"

# Prüfhooks aktivieren (gitleaks vor jedem Commit). core.hooksPath ist lokale Konfiguration,
# das Setzen ist idempotent. Das Ausführbar-Bit muss in den Index (Windows: core.fileMode=false,
# und ohne Bit liefe der Hook auf Linux und macOS nicht) — deshalb wird der Hook als einzige
# Datei schon vorgemerkt, und nur, wenn dieser Lauf ihn angelegt hat. Der Commit bleibt beim
# Menschen.
if [ -f "$DIR/.githooks/pre-commit" ]; then
    if grep -qxF "$DIR/.githooks/pre-commit" "$liste"; then
        git -C "$DIR" add --chmod=+x .githooks/pre-commit
    fi
    # Ein bestehender Hook-Ordner (Husky, lint-staged, eigene Hooks in .git/hooks) wird nicht
    # stillschweigend abgeschaltet: Dann bleibt die Einstellung, und der gitleaks-Aufruf aus
    # .githooks/pre-commit gehört dort hinein — ein Handgriff, der im Bericht steht.
    alt="$(git -C "$DIR" config core.hooksPath 2>/dev/null || true)"
    if [ -n "$alt" ] && [ "$alt" != ".githooks" ]; then
        zeile "Git-Hooks: core.hooksPath bleibt auf '$alt' — den gitleaks-Aufruf aus .githooks/pre-commit dort ergänzen (Handgriff)"
    elif [ -z "$alt" ] && [ -x "$DIR/.git/hooks/pre-commit" ]; then
        zeile "Git-Hooks: .git/hooks/pre-commit besteht — core.hooksPath nicht gesetzt; den gitleaks-Aufruf aus .githooks/pre-commit dort ergänzen (Handgriff)"
    else
        git -C "$DIR" config core.hooksPath .githooks
        zeile "Git-Hooks: core.hooksPath = .githooks (gitleaks vor jedem Commit)"
    fi
fi

zeile "$angelegt Datei(en) angelegt, keine bestehende geändert."

# --------------------------------------------------------------------- Vault
if [ -n "$VAULT" ] && [ -d "$VAULT" ]; then
    meldung "Vault fortschreiben"
    akte="$VAULT/04-projects/$NAME/README.md"
    if [ -f "$akte" ]; then
        zeile "04-projects/$NAME/README.md gibt es schon — nicht angefasst"
    else
        mkdir -p "$(dirname "$akte")"
        cat > "$akte" <<EOF
# $NAME

> Letzte Aktualisierung: $DATUM

$PURPOSE

| | |
|---|---|
| Repo | ${REMOTE:-nur lokal} |
| Stack | $LABEL |
| Kunde/Instanz | $CUSTOMER |
| Ordner | \`$DIR\` |
| Stand | Bestand, am $DATUM in den Firmenstandard aufgenommen (Stufe 0 und 1); Lücken in docs/status.md des Repos |

## Nächste Schritte

1. PR der Aufnahme mergen, Claude Code im Ordner neu starten.
2. Lücken aus docs/status.md je als eigener PR.
EOF
        zeile "04-projects/$NAME/README.md angelegt"
    fi
    daily="$VAULT/05-daily/$DATUM.md"
    mkdir -p "$(dirname "$daily")"
    [ -f "$daily" ] || printf '# %s\n\n' "$DATUM" > "$daily"
    printf -- '- Projekt in den Firmenstandard aufgenommen: [[%s]] (Stack %s)\n' "$NAME" "${STACK:-keiner}" >> "$daily"
    zeile "05-daily/$DATUM.md ergänzt"
elif [ -n "$VAULT" ]; then
    zeile "Vault '$VAULT' gibt es nicht — übersprungen."
fi

# ------------------------------------------------------------------- Bericht
meldung "Fertig — $NAME ist erklärt, Stufe 0 und 1 liegen im Arbeitsbaum"

cat <<EOF

Nächste Schritte (nichts davon macht dieses Skript):

 * CLAUDE.md lesen: Die Befehle stammen aus composer.json, package.json und Makefile —
   Zweck-Spalte in Worten ausfüllen, Unwichtiges streichen, Karte und Fallen ergänzen.
 * docs/decisions/$ADR_NR-aufnahme-firmenstandard.md: Die Lücken stehen unter „Zu tun“.
   Was mit Grund anders bleibt, nach „Bewusst so belassen“ — mit dem Grund.
 * docs/status.md: „Stand“ in ganzen Sätzen, „Nächste Schritte“ in Reihenfolge bringen.
 * Prüfbefehle aus CLAUDE.md einmal laufen lassen; dann auf einem Zweig committen:
       git checkout -b chore/firmenstandard-aufnahme
       git add -A && git commit -m "chore: Aufnahme in den Firmenstandard (Stack ${STACK:-keiner})"
   PR, grüne CI, Squash-Merge — nie direkt auf main.
 * Claude Code in $DIR neu starten (einmaliger Trust-Dialog für den Marketplace) —
   ab dann lädt der SessionStart-Hook Kern und Overlay von selbst.
 * Stufe 2 (Lieferweg) und 3 (Betriebsvertrag): je Punkt ein eigener PR, Vorlagen unter
   templates/${STACK:-<stack>}/dateien/, Regeln im Overlay.
EOF
printf '\n'
