#!/usr/bin/env bash
# projekt-neu.sh — legt ein neues Projekt vollständig nach Firmenstandard an.
#
#     projekt-neu.sh --name <kebab> --stack <name> --purpose "<Zweck>" [Optionen]
#
# Ablauf: prüfen -> Gerüst des Stacks -> Vorlagen kopieren und Platzhalter
# ersetzen -> Einrichtung und erste Prüfung -> git init und ein Commit ->
# optional Repository (Forgejo gitts oder GitHub) -> optional Vault-Eintrag ->
# Abschlussbericht.
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
    projekt-neu.sh --name <kebab> --stack <name> --purpose "<Zweck>" [Optionen]

Pflicht:
    --name <kebab>        Projektname, kebab-case, ASCII (z. B. kunde-werkzeug)
    --stack <name>        einer aus --list-stacks
    --purpose "<text>"    Zweck in ein bis zwei Sätzen

Optionen:
    --forge <forgejo|github>  wo das Repository entsteht (Vorgabe: forgejo, der eigene
                          Git-Server gitts; github für Externe ohne Tailnet und zum Archivieren)
    --owner <owner>       Eigentümer: Organisation oder Konto (Vorgabe bei forgejo: CVS;
                          bei github Pflicht, z. B. CoreVision-Systems-GmbH)
    --forgejo-url <url>   Forgejo-Server (Vorgabe: $FORGEJO_URL oder https://gitts.cvsystems.net)
    --customer "<text>"   Kunde und Instanz (z. B. "Musterkunde auf host1"); ohne Angabe: intern
    --company "<text>"    Rechteinhaber für LICENSE (Vorgabe: CoreVision Systems GmbH)
    --dir <pfad>          Zielordner (Vorgabe: ~/Code/<name>)
    --no-remote           kein Repository anlegen, nur lokal
    --no-github           wie früher: nur lokal, Vorlagen für GitHub (= --forge github --no-remote)
    --vault <pfad>        Vault, in dem Projektseite und Daily Log fortgeschrieben werden
    --list-stacks         verfügbare Stacks auflisten und beenden
    --help                diese Hilfe

Forgejo-Zugang: Token aus $FORGEJO_TOKEN, sonst aus dem Git-Credential-Helper für den
Server (git credential fill). Das Konto braucht die Scopes write:repository und
write:organization.

Beispiele:
    projekt-neu.sh --name musterkunde-wartung --stack script \
        --purpose "Wartungsläufe für die Hosts des Musterkunden." --customer "Musterkunde auf host1"

    projekt-neu.sh --name teilebestand --stack laravel --forge github --owner CoreVision-Systems-GmbH \
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

# Token, Schalter und App der Claude-Durchsicht kann eine Organisation zentral halten
# (CoreVision-Systems-GmbH: Org-Secret und Org-Variable mit Sichtbarkeit „all“, App für alle
# Repos). Am 2026-09-29 genau so passiert: Der Bericht verlangte pauschal ein Repo-Secret, obwohl
# das Org-Secret längst griff — ein unnötiger Token und ein gescheiterter Versuch über '!' in
# Claude Code. Deshalb wird nachgesehen und nur genannt, was wirklich fehlt.
# Verglichen wird auf den erwarteten Wert, nie auf „nicht leer“: Bei einem HTTP-Fehler schreibt
# gh den Fehlertext nach stdout, ohne --jq anzuwenden — das sähe sonst wie ein Treffer aus.
org_secret_da() { # <owner>/<repo>
    [ "$("$GH" api "repos/$1/actions/organization-secrets?per_page=100" \
        --jq '.secrets[] | select(.name == "CLAUDE_CODE_OAUTH_TOKEN") | .name' 2>/dev/null || true)" \
        = CLAUDE_CODE_OAUTH_TOKEN ]
}

org_schalter_an() { # <owner>/<repo>
    [ "$("$GH" api "repos/$1/actions/organization-variables?per_page=100" \
        --jq '.variables[] | select(.name == "CLAUDE_REVIEW_ENABLED") | .value' 2>/dev/null || true)" = true ]
}

# Die Installationen einer Organisation sieht nur ihr Inhaber. Ein Fehler heißt deshalb „nicht
# prüfbar“, nicht „fehlt“ — sonst verlangte der Bericht von einem Mitglied eine Freigabe, die
# längst besteht und die es gar nicht erteilen darf.
org_app_stand() { # <owner> → all | fehlt | unbekannt
    local wert
    if wert="$("$GH" api "orgs/$1/installations?per_page=100" \
        --jq '.installations[] | select(.app_slug == "claude") | .repository_selection' 2>/dev/null)"; then
        case "$wert" in all) echo all ;; *) echo fehlt ;; esac
    else
        echo unbekannt
    fi
}

handgriff_durchsicht() { # <owner> <name>
    local ziel="$1/$2" secret=0 schalter=0 app
    org_secret_da "$ziel" && secret=1
    org_schalter_an "$ziel" && schalter=1
    app="$(org_app_stand "$1")"
    if [ $((secret + schalter)) -eq 2 ] && [ "$app" = all ]; then
        printf ' * Claude-Durchsicht der Pull Requests: nichts zu tun — Token, Schalter und\n'
        printf "   GitHub-App 'Claude' kommen von der Organisation %s.\n" "$1"
        return 0
    fi
    printf ' * Claude-Durchsicht der Pull Requests einschalten:\n'
    if [ "$secret" -eq 0 ]; then
        cat <<EOF
   Token — in einem eigenen Terminal-Fenster (unter Windows: PowerShell),
   NICHT über '!' in Claude Code: 'claude setup-token' braucht einen
   Browser-Login, 'gh secret set' fragt den Wert verdeckt ab.
       claude setup-token
   Im Browser anmelden und erlauben; den ausgegebenen Token (beginnt mit
   sk-ant-oat01-) vollständig kopieren. Dann im selben Fenster:
       gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo $ziel
   Bei der Abfrage einfügen (die Eingabe bleibt unsichtbar) und Enter.
EOF
    fi
    [ "$schalter" -eq 1 ] \
        || printf '   Schalter:\n       gh variable set CLAUDE_REVIEW_ENABLED --body true --repo %s\n' "$ziel"
    case "$app" in
        fehlt) printf "   GitHub-App 'Claude' für %s freigeben: https://github.com/apps/claude\n" "$ziel" ;;
        unbekannt)
            printf "   GitHub-App 'Claude': nicht prüfbar (in einer Organisation sieht die Installationen\n"
            printf '   nur ihr Inhaber, ein Benutzerkonto kennt diese Abfrage nicht). Nachsehen und bei\n'
            printf '   Bedarf für %s freigeben: https://github.com/apps/claude\n' "$ziel" ;;
    esac
}

# ------------------------------------------------------------------- Forgejo
# Token aus der Umgebung oder dem Credential-Helper — dort liegt es ohnehin für git push.
# Nie nachfragen: das Skript läuft ohne Terminal (GCM_INTERACTIVE, GIT_TERMINAL_PROMPT, und
# GIT_ASKPASS leer — im VS-Code-Terminal hinge `git credential fill` sonst am Askpass-Dialog).
# `|| true`: ohne gespeichertes Credential endet git mit 128; unter pipefail bräche das Skript
# sonst stumm ab, statt die Meldung „Kein Forgejo-Token“ zu zeigen.
forgejo_token() {
    if [ -n "${FORGEJO_TOKEN:-}" ]; then
        printf '%s' "$FORGEJO_TOKEN"
        return 0
    fi
    printf 'protocol=%s\nhost=%s\n\n' "${FORGEJO_URL%%://*}" "$FORGEJO_HOST" \
        | GIT_ASKPASS='' GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never git credential fill 2>/dev/null \
        | sed -n 's/^password=//p' | tr -d '\r' || true
}

# Forgejo-API: Antwortkörper nach $FJ_ANTWORT, HTTP-Status nach FJ_STATUS. Das Token geht per
# curl-Konfiguration über stdin, damit es in keiner Prozessliste steht. Der Körper geht über eine
# Datei: Als Argument wandelt das native curl unter Windows Umlaute in die ANSI-Codepage um — am
# 2026-10-16 kam die Repo-Beschreibung so als „f�r“ an.
fj() { # <methode> <pfad> [json-körper]
    [ -z "${3:-}" ] || printf '%s' "$3" > "$FJ_KOERPER"
    FJ_STATUS="$(printf 'header = "Authorization: token %s"\n' "$FJ_TOKEN" \
        | curl -sS -K - -X "$1" -H 'Content-Type: application/json' -H 'Accept: application/json' \
            ${3:+--data-binary "@$FJ_KOERPER"} -o "$FJ_ANTWORT" -w '%{http_code}' "$FORGEJO_URL/api/v1/$2" \
        2>/dev/null)" || FJ_STATUS=000
}

# Erster Wert eines Schlüssels aus der letzten Antwort — genügt für flache Felder wie login.
fj_feld() { # <schlüssel>
    grep -o "\"$1\":\"[^\"]*\"" "$FJ_ANTWORT" | head -1 | sed 's/^"[^"]*":"//; s/"$//'
}

# Wie bei GitHub: Secret und Schalter der Claude-Durchsicht hält die Organisation. Lesen darf
# beides nur ein Owner — ein Mitglied (der Bot) bekommt 403. Das heißt „nicht prüfbar“, nicht
# „fehlt“, sonst verlangte der Bericht eine Einrichtung, die längst besteht.
handgriff_durchsicht_forgejo() { # <owner> <name>
    local secret=unbekannt schalter=unbekannt einstellungen api
    # Gehört das Repo einem Benutzerkonto, gibt es keine Org-Einstellungen — dann die des Repos.
    if [ "$konto" = "$1" ]; then
        api="repos/$1/$2"; einstellungen="$FORGEJO_URL/$1/$2/settings/actions"
    else
        api="orgs/$1"; einstellungen="$FORGEJO_URL/org/$1/settings/actions"
    fi
    fj GET "$api/actions/secrets"
    case "$FJ_STATUS" in
        200) grep -q '"name":"CLAUDE_CODE_OAUTH_TOKEN"' "$FJ_ANTWORT" && secret=ja || secret=nein ;;
        404) secret=nein ;;
    esac
    fj GET "$api/actions/variables/CLAUDE_REVIEW_ENABLED"
    case "$FJ_STATUS" in
        200) grep -q '"data":"true"' "$FJ_ANTWORT" && schalter=ja || schalter=nein ;;
        404) schalter=nein ;;
    esac
    if [ "$secret" = ja ] && [ "$schalter" = ja ]; then
        printf ' * Claude-Durchsicht der Pull Requests: nichts zu tun — Token und Schalter kommen\n'
        printf '   von der Organisation %s.\n' "$1"
        return 0
    fi
    printf ' * Claude-Durchsicht der Pull Requests einschalten (%s):\n' "$1"
    if [ "$secret" = unbekannt ] || [ "$schalter" = unbekannt ]; then
        printf '   Nicht prüfbar: Secrets und Variablen der Organisation sieht nur ein Owner.\n'
        printf '   Ein Owner sieht nach unter %s/secrets und %s/variables:\n' "$einstellungen" "$einstellungen"
        printf '   Secret CLAUDE_CODE_OAUTH_TOKEN und Variable CLAUDE_REVIEW_ENABLED=true.\n'
        return 0
    fi
    if [ "$secret" = nein ]; then
        cat <<EOF
   Token — in einem eigenen Terminal-Fenster (unter Windows: PowerShell),
   NICHT über '!' in Claude Code: 'claude setup-token' braucht einen Browser-Login.
       claude setup-token
   Den ausgegebenen Token (beginnt mit sk-ant-oat01-) vollständig kopieren und als
   Owner im Browser eintragen: $einstellungen/secrets
   → Secret hinzufügen, Name CLAUDE_CODE_OAUTH_TOKEN.
EOF
    fi
    [ "$schalter" = ja ] \
        || printf '   Schalter: %s/variables → Variable CLAUDE_REVIEW_ENABLED mit Wert true.\n' "$einstellungen"
}

stack_lesen() { # <stack> — setzt LABEL DESCRIPTION REQUIRES CONTAINERIZED MARKER
    LABEL=""; DESCRIPTION=""; REQUIRES=""; DATABASE=""; CONTAINERIZED=0; MARKER=0
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
COMPANY="CoreVision Systems GmbH"
DIR=""
FORGE=forgejo
FORGEJO_URL="${FORGEJO_URL:-https://gitts.cvsystems.net}"
MIT_REMOTE=1
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
        --forge)        FORGE="${2:?--forge braucht einen Wert}"; shift 2 ;;
        --forgejo-url)  FORGEJO_URL="${2:?--forgejo-url braucht einen Wert}"; shift 2 ;;
        --no-remote)    MIT_REMOTE=0; shift ;;
        # Altbestand: hieß „nur lokal“, als GitHub der einzige Weg war — bleibt deshalb bei GitHub.
        --no-github)    FORGE=github; MIT_REMOTE=0; shift ;;
        --list-stacks)  stacks_auflisten; exit 0 ;;
        --help|-h)      hilfe; exit 0 ;;
        *)              abbruch "Unbekannte Option: $1 (siehe --help)" ;;
    esac
done

# ------------------------------------------------------------------ Prüfung
meldung "Vorprüfung"

[ -n "$NAME" ]    || abbruch "--name fehlt."
[ -n "$STACK" ]   || abbruch "--stack fehlt (siehe --list-stacks)."
[ -n "$PURPOSE" ] || abbruch "--purpose fehlt."
case "$FORGE" in
    forgejo) [ -n "$OWNER" ] || OWNER=CVS ;;
    github)  [ -n "$OWNER" ] || abbruch "--owner fehlt (bei --forge github Pflicht)." ;;
    *)       abbruch "Unbekannte Forge '$FORGE': forgejo oder github." ;;
esac
FORGEJO_URL="${FORGEJO_URL%/}"
FORGEJO_HOST="${FORGEJO_URL#*://}"; FORGEJO_HOST="${FORGEJO_HOST%%/*}"

printf '%s' "$NAME" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || abbruch "Ungültiger Name '$NAME': kebab-case und ASCII — a-z, 0-9, einzelne Bindestriche, Anfang und Ende alphanumerisch."

# Der Zweck landet unverändert in Quelltexten (JS-Frontmatter, Python-Strings,
# TOML). Ein gerades Anführungszeichen oder ein Backslash bricht dort den Bau.
if printf '%s' "$PURPOSE" | grep -q '["\]'; then
    abbruch "Ungültiger Zweck: gerade Anführungszeichen (\") und Backslash sind nicht erlaubt — sie landen unverändert in Quelltexten. Typografische Anführungszeichen („…“) sind in Ordnung."
fi
# Steuerzeichen (Zeilenumbruch, Tab) machten den JSON-Text für Forgejo ungültig — erst nach dem
# lokalen Commit, ein Halbzustand. grep arbeitet zeilenweise, deshalb über tr gezählt.
[ "$(printf '%s' "$PURPOSE" | tr -d '[:cntrl:]')" = "$PURPOSE" ] \
    || abbruch "Ungültiger Zweck: keine Zeilenumbrüche oder Tabs — ein bis zwei Sätze in einer Zeile."

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
FJ_TOKEN=""
FJ_ANTWORT="$(mktemp)"
FJ_KOERPER="$(mktemp)"
trap 'rm -f "$FJ_ANTWORT" "$FJ_KOERPER"' EXIT
if [ "$MIT_REMOTE" -eq 1 ] && [ "$FORGE" = forgejo ]; then
    command -v curl >/dev/null 2>&1 || abbruch "curl fehlt — für die Forgejo-API nötig. Mit --no-remote nur lokal anlegen."
    FJ_TOKEN="$(forgejo_token)"
    [ -n "$FJ_TOKEN" ] || abbruch "Kein Forgejo-Token für $FORGEJO_HOST: \$FORGEJO_TOKEN setzen oder das Token im Git-Credential-Helper hinterlegen. Mit --no-remote nur lokal anlegen."
    fj GET user
    [ "$FJ_STATUS" = 200 ] || abbruch "Forgejo $FORGEJO_URL lehnt das Token ab oder ist nicht erreichbar (HTTP $FJ_STATUS). Ohne Tailnet: --forge github oder --no-remote."
    konto="$(fj_feld login)"
    [ -n "$konto" ] || abbruch "Forgejo liefert kein Konto zum Token."
    if [ "$konto" != "$OWNER" ]; then
        fj GET "orgs/$OWNER"
        [ "$FJ_STATUS" = 200 ] \
            || abbruch "Das Forgejo-Konto ist '$konto'; '$OWNER' ist weder dieses Konto noch eine erreichbare Organisation (HTTP $FJ_STATUS)."
    fi
    fj GET "repos/$OWNER/$NAME"
    [ "$FJ_STATUS" = 404 ] || abbruch "Das Repository $OWNER/$NAME gibt es auf $FORGEJO_HOST bereits (HTTP $FJ_STATUS)."
    zeile "Forgejo: Konto '$konto', Ziel $FORGEJO_HOST/$OWNER/$NAME"
fi
if [ "$MIT_REMOTE" -eq 1 ] && [ "$FORGE" = github ]; then
    GH="$(gh_pfad)" || abbruch "gh (GitHub CLI) nicht gefunden. Mit --no-remote nur lokal anlegen."
    "$GH" auth status >/dev/null 2>&1 \
        || abbruch "gh ist nicht angemeldet. 'gh auth login' ausführen oder --no-remote nehmen."
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
# Abbild und Repo-Adresse folgen der Forge: Forgejo hat eine eigene Container-Registry unter
# demselben Host, GitHub die ghcr.io.
if [ "$FORGE" = forgejo ]; then
    IMAGE="$FORGEJO_HOST/$OWNER_LC/$NAME"
    REPO_URL="$FORGEJO_URL/$OWNER/$NAME"
else
    IMAGE="ghcr.io/$OWNER_LC/$NAME"
    REPO_URL="https://github.com/$OWNER/$NAME"
fi
DATUM="$(date +%Y-%m-%d)"
JAHR="$(date +%Y)"
# Ablauf der security.txt: Monatserster in einem Jahr — nie mehr als ein Jahr voraus, wie
# RFC 9116 empfiehlt. Aus dem Datum gerechnet, weil `date -d` und `date -v` sich nicht einig sind.
# Jahr und Monat aus demselben Aufruf wie DATUM — zwei date-Aufrufe um Silvester ergäben sonst
# ein Jahr zu viel.
ABLAUF="$(( 10#${DATUM:0:4} + 1 ))-${DATUM:5:2}-01T00:00:00Z"

declare -A ERSATZ=(
    [NAME]="$NAME"
    [NAME_SNAKE]="$NAME_SNAKE"
    [PURPOSE]="$PURPOSE"
    [STACK]="$STACK"
    [STACK_LABEL]="$LABEL"
    # Zieldatenbank aus stack.conf — die KI soll keinen Dialekt raten.
    [DATABASE]="${DATABASE:-keine}"
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
    [EXPIRES]="$ABLAUF"
)

zeile "Projekt:  $NAME"
zeile "Stack:    $STACK ($LABEL)"
zeile "Ordner:   $DIR"
zeile "Repo:     $([ "$MIT_REMOTE" -eq 1 ] && echo "$REPO_URL (privat)" || echo "nur lokal ($FORGE)")"

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
trap 'rm -f "$liste" "$FJ_ANTWORT" "$FJ_KOERPER"' EXIT

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
# Was auf Forgejo anders laufen muss (Claude-Durchsicht ohne GitHub-App), überschreibt die
# GitHub-Fassung. Alles andere bleibt unter .github/ — Forgejo liest es dort mit.
if [ "$FORGE" = forgejo ]; then
    kopieren "$vorlagen/repo-forgejo"
    # release.yml schiebt nach ghcr.io und lädt per gh hoch — auf Forgejo schlüge jeder Tag fehl.
    # Die Forgejo-Fassung mit eigener Registry folgt; bis dahin kein Release-Workflow.
    rm -f "$DIR/.github/workflows/release.yml"
fi

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

chmod +x "$DIR"/deploy/*.sh "$DIR"/scripts/*.sh "$DIR"/tests/*.sh "$DIR"/.githooks/* 2>/dev/null || true

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
# Prüfhooks des Repos (gitleaks vor jedem Commit, .githooks/pre-commit). core.hooksPath ist
# lokale Konfiguration und reist nicht mit: Jeder weitere Klon setzt sie einmal selbst
# (README des Projekts, „Einrichtung“).
git config core.hooksPath .githooks
git add -A
if git diff --cached --quiet; then
    abbruch "Es gibt nichts zu committen — das Gerüst ist leer."
fi

# Ausführbar-Bit im Index setzen. Unter Windows (core.fileMode=false) kommt es
# sonst nie ins Repository, und auf dem Server scheitert ./deploy/update.sh mit
# "Permission denied"; der pre-commit-Hook liefe auf Linux und macOS gar nicht.
for f in deploy/*.sh docker/*.sh scripts/*.sh tests/*.sh .githooks/*; do
    if [ -f "$f" ]; then
        git update-index --chmod=+x "$f"
    fi
done
git commit -q -m "chore: Projektgerüst nach Firmenstandard (Stack $STACK)"
zeile "$(git log -1 --oneline)"

# --------------------------------------------------------------- Repository
SCHUTZ=""
if [ "$MIT_REMOTE" -eq 1 ] && [ "$FORGE" = github ]; then
    meldung "Repository anlegen und hochladen"
    "$GH" repo create "$OWNER/$NAME" --private --source=. --push --description "$PURPOSE"
    zeile "$REPO_URL"
fi
if [ "$MIT_REMOTE" -eq 1 ] && [ "$FORGE" = forgejo ]; then
    meldung "Repository anlegen und hochladen"
    # Der Zweck enthält weder gerades Anführungszeichen noch Backslash (Vorprüfung) — er
    # kann deshalb unverändert in den JSON-Text.
    if [ "$konto" = "$OWNER" ]; then ziel_pfad="user/repos"; else ziel_pfad="orgs/$OWNER/repos"; fi
    fj POST "$ziel_pfad" "{\"name\":\"$NAME\",\"description\":\"$PURPOSE\",\"private\":true,\"default_branch\":\"main\"}"
    [ "$FJ_STATUS" = 201 ] || abbruch "Repository $OWNER/$NAME ließ sich nicht anlegen (HTTP $FJ_STATUS): $(head -c 300 "$FJ_ANTWORT")"
    git remote add origin "$REPO_URL.git"
    # Token als Kopfzeile über die Umgebung, nicht als Argument — so steht es in keiner
    # Prozessliste und nicht in .git/config.
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0="Authorization: token $FJ_TOKEN" \
        git push -q -u origin main
    zeile "$REPO_URL"

    # Wie das Ruleset auf GitHub: nur Squash-Merge, Zweig nach dem Merge weg, auf main nur per
    # PR mit grünem Pflicht-Check 'ci' aus tests.yml. Forgejo benennt den Status
    # „<workflow> / <job> (<ereignis>)“.
    fj PATCH "repos/$OWNER/$NAME" '{"allow_merge_commits":false,"allow_rebase":false,"allow_rebase_explicit":false,"allow_squash_merge":true,"default_merge_style":"squash","default_delete_branch_after_merge":true}'
    merge_status="$FJ_STATUS"
    fj POST "repos/$OWNER/$NAME/branch_protections" '{"rule_name":"main","enable_push":false,"enable_status_check":true,"status_check_contexts":["tests / ci (pull_request)"],"required_approvals":0,"block_on_rejected_reviews":true,"dismiss_stale_approvals":true}'
    if [ "$merge_status" = 200 ] && [ "$FJ_STATUS" = 201 ]; then
        SCHUTZ=gesetzt
        zeile "Hauptzweig geschützt: kein Push auf main, Pflicht-Check 'tests / ci', nur Squash-Merge"
    else
        SCHUTZ="fehlgeschlagen (Einstellungen HTTP $merge_status, Schutzregel HTTP $FJ_STATUS)"
        zeile "Hauptzweig-Schutz: $SCHUTZ"
    fi
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
| Repo | $([ "$MIT_REMOTE" -eq 1 ] && echo "$REPO_URL (privat)" || echo 'nur lokal') |
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
        "$([ "$MIT_REMOTE" -eq 1 ] && echo ", Repo ${REPO_URL#https://}" || echo ', nur lokal')" \
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

if [ "$MIT_REMOTE" -eq 1 ] && [ "$FORGE" = forgejo ]; then
    handgriff_durchsicht_forgejo "$OWNER" "$NAME"
    if [ "$SCHUTZ" != gesetzt ]; then
        cat <<EOF
 * Hauptzweig von Hand schützen — $SCHUTZ. Als Admin des Repos unter
   $REPO_URL/settings/branches: Regel für main, Push aus, Statusprüfung
   'tests / ci (pull_request)'; unter $REPO_URL/settings nur Squash-Merge.
EOF
    fi
    cat <<EOF
 * Abhängigkeiten: .github/dependabot.yml wirkt auf Forgejo nicht. Bis Renovate
   eingerichtet ist, Aktualisierungen von Hand prüfen.
 * Release-Workflow und Container-Registry für Forgejo folgen in einer späteren
   Fassung des Standards; bis dahin hat das Projekt kein release.yml.
EOF
elif [ "$MIT_REMOTE" -eq 1 ]; then
    handgriff_durchsicht "$OWNER" "$NAME"
    cat <<EOF
 * Hauptzweig schützen (PR-Pflicht, Pflicht-Check 'ci', kein Force-Push,
   Squash-Merge):
       bash <pfad-zu>/claude-standard/scripts/apply-rulesets.sh $OWNER/$NAME
   In der Organisation setzt das nur die Custom Property ci-check=ci, das
   Org-Ruleset greift sofort. Auf einem Benutzerkonto entsteht ein Repo-Ruleset;
   private Repos brauchen dafür einen bezahlten Plan (sonst 403, dann bleibt der
   Hook git-guard die einzige Absicherung).
EOF
elif [ "$FORGE" = forgejo ]; then
    cat <<EOF
 * Kein Repository angelegt (--no-remote). Wenn es eines geben soll: auf
   $FORGEJO_URL ein privates Repository $OWNER/$NAME ohne Inhalt anlegen, dann
       git remote add origin $FORGEJO_URL/$OWNER/$NAME.git && git push -u origin main
   Danach Hauptzweig-Schutz und Claude-Durchsicht wie im README des Standards.
EOF
else
    cat <<EOF
 * Kein Repository angelegt (--no-remote). Wenn es eines geben soll:
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
