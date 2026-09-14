#!/usr/bin/env bash
# projekt-neu.sh — legt ein neues Projekt vollständig nach Firmenstandard an.
#
#     projekt-neu.sh --name <kebab> --stack <name> --owner <github-owner> \
#                    --purpose "<Zweck>" [Optionen]
#
# Ablauf: prüfen -> Gerüst des Stacks -> Vorlagen kopieren und Platzhalter
# ersetzen -> Einrichtung und erste Prüfung -> git init und ein Commit ->
# optional GitHub-Repo -> optional Vault-Eintrag -> Abschlussbericht.
#
# Das Skript ist deterministisch: gleiche Eingabe, gleiches Ergebnis. Es fragt
# nichts nach; alles, was es wissen muss, steht in den Argumenten.
#
# Ein Stack besteht aus zwei Teilen:
#   stacks/<name>.md            das Overlay (Regeln), geladen vom SessionStart-Hook
#   templates/<name>/stack.conf das Register (LABEL, DESCRIPTION, REQUIRES, ...)
#   templates/<name>/befehle.md der Befehlsblock für die CLAUDE.md des Projekts
#   templates/<name>/scaffold.sh  optional: Installer und Einrichtung
#   templates/<name>/dateien/   alles, was ins Projekt kopiert wird
#
# Gemeinsam für alle Stacks: templates/repo/

set -euo pipefail

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
vorlagen="$root/templates"

# --------------------------------------------------------------- Hilfsmittel
meldung()  { printf '\n== %s\n' "$1"; }
zeile()    { printf '   %s\n' "$1"; }
abbruch()  { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

hilfe() {
    cat <<'EOF'
projekt-neu.sh — neues Projekt nach Firmenstandard anlegen.

Aufruf:
    projekt-neu.sh --name <kebab> --stack <name> --owner <github-owner> \
                   --purpose "<Zweck>" [Optionen]

Pflicht:
    --name <kebab>        Projektname, kebab-case, ASCII (z. B. kunde-werkzeug)
    --stack <name>        einer aus --list-stacks
    --owner <owner>       GitHub-Eigentümer (z. B. CoreVision-Systems-GmbH)
    --purpose "<text>"    Zweck in ein bis zwei Sätzen

Optionen:
    --customer "<text>"   Kunde und Instanz (z. B. "Musterkunde auf host1"); ohne Angabe: intern
    --company "<text>"    Rechteinhaber für LICENSE (Vorgabe: CoreVision Systems / PCN GmbH)
    --dir <pfad>          Zielordner (Vorgabe: ~/Code/<name>)
    --no-github           kein Repository anlegen, nur lokal
    --vault <pfad>        Vault, in dem Projektseite und Daily Log fortgeschrieben werden
    --list-stacks         verfügbare Stacks auflisten und beenden
    --help                diese Hilfe

Beispiele:
    projekt-neu.sh --name musterkunde-wartung --stack script --owner CoreVision-Systems-GmbH \
        --purpose "Wartungsläufe für die Hosts des Musterkunden." --customer "Musterkunde auf host1"

    projekt-neu.sh --name teilebestand --stack laravel --owner CoreVision-Systems-GmbH \
        --purpose "Teilebestand mit Verwaltung und Außendienst-Oberfläche." \
        --vault ~/Vaults/mein-vault
EOF
}

# Ersetzt {{SCHLUESSEL}} in einer Datei. Reines bash — envsubst gibt es unter
# Windows nicht, und sed müsste jeden Wert maskieren.
#
# Achtung: Im Ersatzteil von ${var//muster/ersatz} sind Backslash und
# kaufmännisches Und Sonderzeichen — `&` steht dort für den Treffer selbst.
# Ein Befehl wie `a && b` würde sonst zu `a {{X}}{{X}} b`. Deshalb beide
# maskieren, Backslash zuerst.
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

# Findet ein Werkzeug, auch als .bat und im Herd-Verzeichnis (Windows).
werkzeug_da() {
    local n="$1" k
    command -v "$n" >/dev/null 2>&1 && return 0
    command -v "$n.bat" >/dev/null 2>&1 && return 0
    for k in "$HOME/.config/herd/bin/$n.bat" "$HOME/.config/herd/bin/$n.phar" \
             "$HOME/.config/herd/bin/$n"; do
        [ -f "$k" ] && return 0
    done
    return 1
}

gh_pfad() {
    if command -v gh >/dev/null 2>&1; then
        printf 'gh'
    elif [ -x "/c/Program Files/GitHub CLI/gh.exe" ]; then
        printf '/c/Program Files/GitHub CLI/gh.exe'
    else
        return 1
    fi
}

stack_lesen() { # <stack> — setzt LABEL DESCRIPTION REQUIRES CONTAINERIZED MARKER
    LABEL=""; DESCRIPTION=""; REQUIRES=""; CONTAINERIZED=0; MARKER=0
    # shellcheck disable=SC1090
    . "$vorlagen/$1/stack.conf"
}

stacks_auflisten() {
    local konf name
    printf 'Verfügbare Stacks:\n\n'
    for konf in "$vorlagen"/*/stack.conf; do
        [ -f "$konf" ] || continue
        name="$(basename "$(dirname "$konf")")"
        case "$name" in _*) continue ;; esac
        stack_lesen "$name"
        printf '  %-10s %s\n' "$name" "$LABEL"
        printf '  %-10s %s\n' "" "$DESCRIPTION"
        printf '  %-10s braucht: %s | Abbild: %s\n\n' "" "${REQUIRES:-nichts}" \
            "$([ "$CONTAINERIZED" = "1" ] && echo ja || echo nein)"
    done
}

# ----------------------------------------------------------------- Argumente
NAME=""; STACK=""; OWNER=""; PURPOSE=""
CUSTOMER="intern"
COMPANY="CoreVision Systems / PCN GmbH"
DIR=""
MIT_GITHUB=1
VAULT=""

[ $# -eq 0 ] && { hilfe; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --name)         NAME="${2:?--name braucht einen Wert}"; shift 2 ;;
        --stack)        STACK="${2:?--stack braucht einen Wert}"; shift 2 ;;
        --owner)        OWNER="${2:?--owner braucht einen Wert}"; shift 2 ;;
        --purpose)      PURPOSE="${2:?--purpose braucht einen Wert}"; shift 2 ;;
        --customer)     CUSTOMER="${2:?--customer braucht einen Wert}"; shift 2 ;;
        --company)      COMPANY="${2:?--company braucht einen Wert}"; shift 2 ;;
        --dir)          DIR="${2:?--dir braucht einen Wert}"; shift 2 ;;
        --vault)        VAULT="${2:?--vault braucht einen Wert}"; shift 2 ;;
        --no-github)    MIT_GITHUB=0; shift ;;
        --list-stacks)  stacks_auflisten; exit 0 ;;
        --help|-h)      hilfe; exit 0 ;;
        *)              abbruch "Unbekannte Option: $1 (siehe --help)" ;;
    esac
done

# ------------------------------------------------------------------ Prüfung
meldung "Vorprüfung"

[ -n "$NAME" ]    || abbruch "--name fehlt."
[ -n "$STACK" ]   || abbruch "--stack fehlt (siehe --list-stacks)."
[ -n "$OWNER" ]   || abbruch "--owner fehlt."
[ -n "$PURPOSE" ] || abbruch "--purpose fehlt."

printf '%s' "$NAME" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || abbruch "Ungültiger Name '$NAME': kebab-case und ASCII — a-z, 0-9, einzelne Bindestriche, Anfang und Ende alphanumerisch."

# Der Zweck landet unverändert in Quelltexten (JS-Frontmatter, Python-Strings,
# TOML). Ein gerades Anführungszeichen oder ein Backslash bricht dort den Bau.
if printf '%s' "$PURPOSE" | grep -q '["\]'; then
    abbruch "Ungültiger Zweck: gerade Anführungszeichen (\") und Backslash sind nicht erlaubt — sie landen unverändert in Quelltexten. Typografische Anführungszeichen („…“) sind in Ordnung."
fi

[ -f "$vorlagen/$STACK/stack.conf" ] \
    || abbruch "Unbekannter Stack '$STACK'. Verfügbar: $(
        for k in "$vorlagen"/*/stack.conf; do
            n="$(basename "$(dirname "$k")")"; case "$n" in _*) continue ;; esac; printf '%s ' "$n"
        done)"

[ -f "$root/stacks/$STACK.md" ] \
    || zeile "Hinweis: Für '$STACK' gibt es kein Overlay stacks/$STACK.md — es gilt nur der Kern."

stack_lesen "$STACK"

fehlend=""
for w in $REQUIRES; do
    werkzeug_da "$w" || fehlend="$fehlend $w"
done
[ -z "$fehlend" ] || abbruch "Diese Werkzeuge fehlen im PATH:$fehlend"

[ -n "$DIR" ] || DIR="$HOME/Code/$NAME"
case "$DIR" in
    /*|[A-Za-z]:*) ;;
    *) DIR="$(pwd)/$DIR" ;;
esac

if [ -e "$DIR" ]; then
    [ -d "$DIR" ] || abbruch "'$DIR' ist eine Datei, kein Verzeichnis."
    [ -z "$(ls -A "$DIR" 2>/dev/null)" ] \
        || abbruch "Der Zielordner '$DIR' ist nicht leer."
fi

GH=""
konto=""
if [ "$MIT_GITHUB" -eq 1 ]; then
    GH="$(gh_pfad)" || abbruch "gh (GitHub CLI) nicht gefunden. Mit --no-github nur lokal anlegen."
    "$GH" auth status >/dev/null 2>&1 \
        || abbruch "gh ist nicht angemeldet. 'gh auth login' ausführen oder --no-github nehmen."
    konto="$("$GH" api user --jq '.login' 2>/dev/null || true)"
    [ -n "$konto" ] || abbruch "gh liefert kein aktives Konto."
    if [ "$konto" != "$OWNER" ]; then
        "$GH" api "orgs/$OWNER" >/dev/null 2>&1 \
            || abbruch "Das aktive gh-Konto ist '$konto'; '$OWNER' ist weder dieses Konto noch eine erreichbare Organisation. 'gh auth switch --user $OWNER' oder --owner korrigieren."
    fi
    "$GH" repo view "$OWNER/$NAME" >/dev/null 2>&1 \
        && abbruch "Das Repository $OWNER/$NAME gibt es bereits."
    zeile "GitHub: aktives Konto '$konto', Ziel $OWNER/$NAME"
fi

# ---------------------------------------------------------------- Platzhalter
OWNER_LC="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
NAME_SNAKE="$(printf '%s' "$NAME" | tr '-' '_')"
# Präfix für Umgebungsvariablen: letztes Namensglied, gross, mit Unterstrich.
ENV_PREFIX="$(printf '%s' "${NAME##*-}" | tr '[:lower:]' '[:upper:]')_"
IMAGE="ghcr.io/$OWNER_LC/$NAME"
DATUM="$(date +%Y-%m-%d)"
JAHR="$(date +%Y)"

declare -A ERSATZ=(
    [NAME]="$NAME"
    [NAME_SNAKE]="$NAME_SNAKE"
    [PURPOSE]="$PURPOSE"
    [STACK]="$STACK"
    [STACK_LABEL]="$LABEL"
    [OWNER]="$OWNER"
    [OWNER_LC]="$OWNER_LC"
    # CODEOWNERS braucht einen Benutzer oder ein Team, keine Organisation: bei
    # einer Organisation als Eigentümer steht dort das aktive gh-Konto.
    [OWNER_USER]="${konto:-$OWNER}"
    [COMPANY]="$COMPANY"
    [CUSTOMER]="$CUSTOMER"
    [IMAGE]="$IMAGE"
    [ENV_PREFIX]="$ENV_PREFIX"
    [DATE]="$DATUM"
    [YEAR]="$JAHR"
)

zeile "Projekt:  $NAME"
zeile "Stack:    $STACK ($LABEL)"
zeile "Ordner:   $DIR"
zeile "Repo:     $([ "$MIT_GITHUB" -eq 1 ] && echo "$OWNER/$NAME (privat)" || echo 'nur lokal')"

export NAME DIR OWNER IMAGE PURPOSE ENV_PREFIX

# ------------------------------------------------------------ Phase 1: Gerüst
meldung "Gerüst anlegen"
if [ -f "$vorlagen/$STACK/scaffold.sh" ]; then
    PHASE=geruest bash "$vorlagen/$STACK/scaffold.sh"
else
    mkdir -p "$DIR"
fi
mkdir -p "$DIR"

# ------------------------------------------------------------ Vorlagen kopieren
meldung "Vorlagen einsetzen"

# Der Befehlsblock des Stacks landet später anstelle von {{COMMANDS}}.
if [ -f "$vorlagen/$STACK/befehle.md" ]; then
    ERSATZ[COMMANDS]="$(cat "$vorlagen/$STACK/befehle.md")"
else
    ERSATZ[COMMANDS]="<!-- Befehle des Projekts eintragen. -->"
fi

# Kopiert und merkt sich dabei, welche Zieldateien aus Vorlagen stammen. Nur in
# diesen wird ersetzt und nur diese werden auf Reste geprüft — der Rest des
# Projekts (vendor, node_modules, Blade-Ansichten) geht das nichts an.
liste="$(mktemp)"
trap 'rm -f "$liste"' EXIT

kopieren() { # <quellordner>
    [ -d "$1" ] || return 0
    local f
    while IFS= read -r f; do
        printf '%s/%s\n' "$DIR" "${f#"$1"/}" >> "$liste"
    done < <(find "$1" -type f)
    cp -R "$1/." "$DIR/"
}

kopieren "$vorlagen/repo"
kopieren "$vorlagen/$STACK/dateien"

sort -u "$liste" -o "$liste"

anzahl=0
while IFS= read -r datei; do
    [ -f "$datei" ] || continue
    ersetzen_in_datei "$datei"
    anzahl=$((anzahl + 1))
done < "$liste"
zeile "$anzahl Dateien aus Vorlagen eingesetzt"

# Ein übrig gebliebener {{GROSSBUCHSTABEN}}-Platzhalter ist ein Fehler in einer
# Vorlage. Go-Templates wie {{.Ports}} oder {{version}} bleiben absichtlich stehen.
rest=""
while IFS= read -r datei; do
    [ -f "$datei" ] || continue
    if grep -qE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$datei"; then
        rest="$rest
  $datei"
    fi
done < "$liste"
[ -z "$rest" ] || abbruch "Unersetzte Platzhalter in:$rest"

chmod +x "$DIR"/deploy/*.sh "$DIR"/scripts/*.sh "$DIR"/tests/*.sh 2>/dev/null || true

# Markerdatei für Stacks, die der SessionStart-Hook nicht selbst erkennt.
if [ "$MARKER" = "1" ]; then
    printf 'stack: %s\n' "$STACK" > "$DIR/.coding-standard"
    zeile "Markerdatei .coding-standard geschrieben (stack: $STACK)"
fi

# -------------------------------------------------------- Phase 2: Einrichten
meldung "Einrichten und einmal prüfen"
if [ -f "$vorlagen/$STACK/scaffold.sh" ]; then
    PHASE=einrichten bash "$vorlagen/$STACK/scaffold.sh"
else
    zeile "Der Stack bringt keine Einrichtung mit."
fi

# ----------------------------------------------------------------------- Git
meldung "Erster Commit"
cd "$DIR"
if [ ! -d .git ]; then
    git init -b main >/dev/null
fi
git add -A
if git diff --cached --quiet; then
    abbruch "Es gibt nichts zu committen — das Gerüst ist leer."
fi

# Ausführbar-Bit im Index setzen. Unter Windows (core.fileMode=false) kommt es
# sonst nie ins Repository, und auf dem Server scheitert ./deploy/update.sh mit
# "Permission denied".
for f in deploy/*.sh docker/*.sh scripts/*.sh tests/*.sh; do
    if [ -f "$f" ]; then
        git update-index --chmod=+x "$f"
    fi
done
git commit -q -m "chore: Projektgerüst nach Firmenstandard (Stack $STACK)"
zeile "$(git log -1 --oneline)"

# -------------------------------------------------------------------- GitHub
if [ "$MIT_GITHUB" -eq 1 ]; then
    meldung "Repository anlegen und hochladen"
    "$GH" repo create "$OWNER/$NAME" --private --source=. --push --description "$PURPOSE"
    zeile "https://github.com/$OWNER/$NAME"
fi

# --------------------------------------------------------------------- Vault
if [ -n "$VAULT" ] && [ -d "$VAULT" ]; then
    meldung "Vault fortschreiben"

    projektseite="$VAULT/04-projects/$NAME/README.md"
    mkdir -p "$(dirname "$projektseite")"
    cat > "$projektseite" <<EOF
# $NAME

> Letzte Aktualisierung: $DATUM

$PURPOSE

| | |
|---|---|
| Repo | $([ "$MIT_GITHUB" -eq 1 ] && echo "https://github.com/$OWNER/$NAME (privat)" || echo 'nur lokal') |
| Stack | $LABEL |
| Kunde/Instanz | $CUSTOMER |
| Ordner | \`$DIR\` |
| Stand | Gerüst nach Firmenstandard angelegt, noch nicht ausgerollt |

## Nächste Schritte

1. Offene Handgriffe aus dem Abschlussbericht von \`/projekt-neu\` erledigen.
2. Erstes Feature planen.
EOF
    zeile "04-projects/$NAME/README.md angelegt"

    daily="$VAULT/05-daily/$DATUM.md"
    mkdir -p "$(dirname "$daily")"
    [ -f "$daily" ] || printf '# %s\n\n' "$DATUM" > "$daily"
    printf -- '- Projekt angelegt: [[%s]] (Stack %s%s)\n' \
        "$NAME" "$STACK" \
        "$([ "$MIT_GITHUB" -eq 1 ] && echo ", Repo github.com/$OWNER/$NAME" || echo ', nur lokal')" \
        >> "$daily"
    zeile "05-daily/$DATUM.md ergänzt"
elif [ -n "$VAULT" ]; then
    zeile "Vault '$VAULT' gibt es nicht — übersprungen."
fi

# ------------------------------------------------------------------- Bericht
meldung "Fertig — $NAME steht in $DIR"

cat <<EOF

Offene Handgriffe (nichts davon macht dieses Skript):

 * Claude Code in $DIR neu starten. Beim ersten Start fragt es einmal nach
   Vertrauen für den Marketplace 'corevision' (Trust-Dialog). Danach lädt der
   SessionStart-Hook Kern und Stack-Overlay von selbst.
EOF

if [ "$MIT_GITHUB" -eq 1 ]; then
    cat <<EOF
 * Claude-Durchsicht der Pull Requests einschalten:
       claude setup-token
       gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo $OWNER/$NAME
       gh variable set CLAUDE_REVIEW_ENABLED --body true --repo $OWNER/$NAME
   Dazu die GitHub-App 'Claude' für $OWNER/$NAME freigeben.
 * Hauptzweig schützen (PR-Pflicht, Pflicht-Check 'ci', kein Force-Push,
   Squash-Merge):
       bash <pfad-zu>/claude-standard/scripts/apply-rulesets.sh $OWNER/$NAME
   In der Organisation setzt das nur die Custom Property ci-check=ci, das
   Org-Ruleset greift sofort. Auf einem Benutzerkonto entsteht ein Repo-Ruleset;
   private Repos brauchen dafür einen bezahlten Plan (sonst 403, dann bleibt der
   Hook git-guard die einzige Absicherung).
EOF
else
    cat <<EOF
 * Kein Repository angelegt (--no-github). Wenn es eines geben soll:
       gh repo create $OWNER/$NAME --private --source=. --push --description "$PURPOSE"
   Danach Geheimnis, Variable und Ruleset wie im README des Standards.
EOF
fi

if [ "$CUSTOMER" != "intern" ]; then
    cat <<EOF
 * Kundeninstanz ($CUSTOMER): Instanzordner im 'deployments'-Repo anlegen und die
   .env dort aus dem KeePassXC-Tresor befüllen — nie aus dem Repository.
EOF
fi

cat <<EOF
 * Erster Release, sobald etwas Lauffähiges steht: /release
EOF

if [ -f "$DIR/.projekt-neu-nacharbeit" ]; then
    printf '\nNacharbeit aus dem Gerüst:\n'
    sed 's/^/ - /' "$DIR/.projekt-neu-nacharbeit"
fi

printf '\n'
