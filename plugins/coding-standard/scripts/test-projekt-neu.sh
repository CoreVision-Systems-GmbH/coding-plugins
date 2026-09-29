#!/usr/bin/env bash
# Prüft projekt-neu.sh: Argumentprüfung, Stack-Register und vier echte Proben.
#
#     bash plugins/coding-standard/scripts/test-projekt-neu.sh
#
# Die Proben laufen mit --no-github oder gegen eine gh-Attrappe in einem
# Wegwerf-Verzeichnis; es entsteht kein Repository auf GitHub und nichts
# außerhalb von $TMPDIR. Die
# FastAPI-Probe legt eine virtuelle Umgebung an und installiert die gepinnten
# Abhängigkeiten — das dauert eine halbe bis eine Minute. Die Astro-Probe lädt
# die npm-Abhängigkeiten aus dem Netz, baut die Site und prüft dist/ — noch
# einmal etwa eine Minute. Die WordPress-Probe installiert die Composer-
# Abhängigkeiten samt WordPress-Kern und lässt PHPCS, PHPStan und die
# Strukturprüfung laufen — ein bis zwei Minuten.
#
# Laravel ist bewusst nicht dabei: `laravel new` samt Filament braucht mehrere
# Minuten und einen Composer-Cache. Diese Probe wird von Hand gefahren.

set -u

hier="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$hier/.." && pwd)"
skript="$hier/projekt-neu.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fehler=0
ok()     { echo "ok     $1"; }
nichtok() { echo "FEHLER $1"; fehler=$((fehler + 1)); }

# probe_vscode <projekt> — die drei Editor-Dateien sind gültiges JSON, im Repo verfolgt (nicht
# von .gitignore geschluckt), und die Aufgaben rufen Skripte, die es im Gerüst gibt.
probe_vscode() {
    local p="$1" f fehlt=""
    for f in settings extensions tasks; do
        python -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$p/.vscode/$f.json" 2>/dev/null || fehlt="$fehlt $f.json"
    done
    [ -z "$fehlt" ] && ok ".vscode: gültiges JSON" || nichtok ".vscode: gültiges JSON (ungültig:$fehlt)"
    [ "$(git -C "$p" ls-files .vscode | wc -l)" -eq 3 ] \
        && ok ".vscode: drei Dateien im Repo verfolgt" || nichtok ".vscode: drei Dateien im Repo verfolgt (gezählt: $(git -C "$p" ls-files .vscode | wc -l))"
    # Unter Windows endet die Python-Ausgabe mit \r — das machte aus deploy/dev.sh eine fremde Datei;
    # und ein Python-Fehler darf nicht als leere Liste durchgehen.
    local roh
    if roh="$(python -c "import json,sys,re; [print(m) for t in json.load(open(sys.argv[1], encoding='utf-8'))['tasks'] for m in re.findall(r'(?:scripts|deploy)/[a-z-]+\.sh', t['command'])]" "$p/.vscode/tasks.json" 2>/dev/null)"; then
        fehlt=""
        for f in $(printf '%s\n' "$roh" | tr -d '\r' | sort -u); do
            [ -f "$p/$f" ] || fehlt="$fehlt $f"
        done
        [ -z "$fehlt" ] && ok ".vscode/tasks.json: alle gerufenen Skripte vorhanden" || nichtok ".vscode/tasks.json: alle gerufenen Skripte vorhanden (fehlt:$fehlt)"
    else
        nichtok ".vscode/tasks.json: alle gerufenen Skripte vorhanden (tasks.json nicht lesbar oder ohne tasks)"
    fi
}

# probe_komplexitaet <projekt> [werkzeug] — das Gerüst ist ohne Befund, und das genannte Werkzeug
# ist wirklich gelaufen („== ruff“, „== PHPMD“): ein fehlendes Werkzeug wäre sonst stilles Grün.
probe_komplexitaet() {
    local p="$1" werkzeug="${2:-}" aus status
    aus="$(cd "$p" && bash scripts/komplexitaet-pruefen.sh 2>&1)" && status=0 || status=$?
    if [ "$status" -eq 0 ] && ! printf '%s\n' "$aus" | grep -q 'WARN: Komplexität' \
        && { [ -z "$werkzeug" ] || printf '%s\n' "$aus" | grep -q "^== $werkzeug"; }; then
        ok "scripts/komplexitaet-pruefen.sh: Gerüst ohne Befund${werkzeug:+ ($werkzeug gelaufen)}"
    else
        nichtok "scripts/komplexitaet-pruefen.sh: Gerüst ohne Befund${werkzeug:+ ($werkzeug gelaufen)} (Status $status): $(printf '%s\n' "$aus" | grep -E 'WARN|Hinweis|Befund|==' | head -4 | tr '\n' ' ')"
    fi
}

# probe_konfig_lizenzen <projekt> — beide Prüfer müssen wirklich geprüft haben: „Konfiguration:
# sauber“ und, sobald Abhängigkeiten installiert sind, „Pakete geprüft“. Ein Exit 0 allein wäre
# auch bei „nichts geprüft“ grün — stilles Grün, genau das, was die Skripte verhindern sollen.
probe_konfig_lizenzen() {
    local p="$1" aus erwartet='Lizenzen: '
    if aus="$(cd "$p" && bash scripts/konfig-pruefen.sh 2>&1)" && printf '%s\n' "$aus" | grep -q '^Konfiguration: sauber\.'; then
        ok "scripts/konfig-pruefen.sh: Gerüst ist sauber"
    else
        nichtok "scripts/konfig-pruefen.sh: Gerüst ist sauber: $(printf '%s\n' "$aus" | grep -E 'BEFUND|FEHLER' | head -3 | tr '\n' ' ')"
    fi
    if [ -d "$p/vendor" ] || [ -d "$p/node_modules" ] || [ -d "$p/.venv" ]; then erwartet='Pakete geprüft'; fi
    if aus="$(cd "$p" && bash scripts/lizenzen-pruefen.sh 2>&1)" && printf '%s\n' "$aus" | grep -q "$erwartet"; then
        ok "scripts/lizenzen-pruefen.sh: keine Befunde im Gerüst ($(printf '%s\n' "$aus" | grep '^Lizenzen:' | tail -1))"
    else
        nichtok "scripts/lizenzen-pruefen.sh: keine Befunde im Gerüst: $(printf '%s\n' "$aus" | grep -E 'BEFUND|^Lizenzen:' | head -3 | tr '\n' ' ')"
    fi
}

behaupte() { # <name> <status 0=gut>
    if [ "$2" -eq 0 ]; then ok "$1"; else nichtok "$1"; fi
}

lauf() { # <erwarteter ausgangswert> <name> <argumente...>
    local erwartet="$1" name="$2"
    shift 2
    local ausgabe status
    ausgabe="$(bash "$skript" "$@" 2>&1)"
    status=$?
    if [ "$status" -eq "$erwartet" ]; then
        ok "$name"
    else
        nichtok "$name (Ausgangswert $status, erwartet $erwartet)"
        printf '%s\n' "$ausgabe" | tail -5 | sed 's/^/       | /'
    fi
    LETZTE_AUSGABE="$ausgabe"
}

hook_stacks() { # <projektdir> → Zeile "Stack erkannt: ..."
    (cd "$1" && env CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$1" \
        bash "$root/hooks/standard-context.sh") | head -1
}

echo "== Argumente und Register"

lauf 0 "--help endet sauber" --help
lauf 0 "--list-stacks endet sauber" --list-stacks

for s in laravel fastapi script astro wordpress; do
    if grep -q "^  $s " <<<"$LETZTE_AUSGABE"; then
        ok "--list-stacks nennt $s"
    else
        nichtok "--list-stacks nennt $s"
    fi
done

if grep -q '_vorlage' <<<"$LETZTE_AUSGABE"; then
    nichtok "--list-stacks zeigt _vorlage nicht"
else
    ok "--list-stacks zeigt _vorlage nicht"
fi

lauf 1 "ungültiger Name wird abgewiesen" \
    --name "Mein_Projekt" --stack script --owner musterorg --purpose "Probe." --no-github
grep -q 'kebab-case' <<<"$LETZTE_AUSGABE" \
    && ok "Meldung nennt kebab-case" || nichtok "Meldung nennt kebab-case"

lauf 1 "unbekannter Stack wird abgewiesen" \
    --name probe --stack rubyonrails --owner musterorg --purpose "Probe." --no-github
grep -q 'Unbekannter Stack' <<<"$LETZTE_AUSGABE" \
    && ok "Meldung nennt den unbekannten Stack" || nichtok "Meldung nennt den unbekannten Stack"

lauf 1 "fehlendes --purpose wird abgewiesen" \
    --name probe --stack script --owner musterorg --no-github

lauf 1 "Zweck mit geradem Anführungszeichen wird abgewiesen" \
    --name probe --stack script --owner musterorg --purpose 'Werkzeug für "Muster" GmbH.' --no-github
grep -q 'Anführungszeichen' <<<"$LETZTE_AUSGABE" \
    && ok "Meldung nennt Anführungszeichen" || nichtok "Meldung nennt Anführungszeichen"

lauf 1 "Zweck mit Backslash wird abgewiesen" \
    --name probe --stack script --owner musterorg --purpose 'Pfad C:\dev.' --no-github

# Fehlende Werkzeuge: PATH und HOME so einengen, dass weder php noch node
# gefunden werden — auch nicht über das Herd-Verzeichnis.
mkdir -p "$tmp/leeres-heim"
ausgabe="$(env PATH=/usr/bin:/bin HOME="$tmp/leeres-heim" bash "$skript" \
    --name probe --stack laravel --owner musterorg --purpose "Probe." \
    --dir "$tmp/nie" --no-github 2>&1)"
status=$?
behaupte "fehlende Werkzeuge brechen ab" "$([ "$status" -ne 0 ] && echo 0 || echo 1)"
grep -q 'Werkzeuge fehlen' <<<"$ausgabe" \
    && ok "Meldung listet die fehlenden Werkzeuge" || nichtok "Meldung listet die fehlenden Werkzeuge"

# Nicht leerer Zielordner
mkdir -p "$tmp/belegt" && touch "$tmp/belegt/etwas"
lauf 1 "nicht leerer Zielordner wird abgewiesen" \
    --name probe --stack script --owner musterorg --purpose "Probe." \
    --dir "$tmp/belegt" --no-github

# ---------------------------------------------------------------- Probe script
echo
echo "== Probe: Stack script"

pdir="$tmp/probe-script"
lauf 0 "Projekt entsteht" \
    --name probe-script --stack script --owner musterorg \
    --purpose "Wegwerfprobe des Bootstraps." --dir "$pdir" --no-github

for datei in CLAUDE.md README.md CHANGES.md LICENSE version.txt .gitignore SECURITY.md \
             .editorconfig .gitattributes .coding-standard \
             .githooks/pre-commit .gitleaks.toml \
             .claude/settings.json .claude/rules/tests.md \
             .github/CODEOWNERS .github/dependabot.yml \
             .github/pull_request_template.md .github/workflows/tests.yml scripts/pr-text-pruefen.sh \
             .github/workflows/claude-review.yml \
             docs/status.md docs/decisions/0001-projektstart.md \
             scripts/beispiel.sh scripts/beispiel.py scripts/check.sh scripts/komplexitaet-pruefen.sh \
             .vscode/settings.json .vscode/extensions.json .vscode/tasks.json \
             tests/test_beispiel.py tests/test_beispiel_sh.sh; do
    [ -f "$pdir/$datei" ] && ok "vorhanden: $datei" || nichtok "fehlt: $datei"
done

[ -f "$pdir/Dockerfile" ] \
    && nichtok "script-Stack liefert kein Dockerfile" \
    || ok "script-Stack liefert kein Dockerfile"

grep -rlE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$pdir" >/dev/null 2>&1 \
    && nichtok "keine unersetzten Platzhalter" \
    || ok "keine unersetzten Platzhalter"
# Erste Datenzeile der Befehlstabelle (nach Kopf und Trennlinie) ist der eine Prüfbefehl.
awk '/^## Befehle/{f=1;next} f&&/^\|/&&!/^\| Zweck/&&!/^\| *-/{print;exit}' "$pdir/CLAUDE.md" | grep -q 'Alles prüfen' \
    && ok "CLAUDE.md nennt den Prüfbefehl zuerst" || nichtok "CLAUDE.md nennt den Prüfbefehl zuerst"

grep -q 'probe-script' "$pdir/CLAUDE.md" \
    && ok "CLAUDE.md trägt den Projektnamen" || nichtok "CLAUDE.md trägt den Projektnamen"
bash "$pdir/scripts/pr-text-pruefen.sh" "$pdir/.github/pull_request_template.md" >/dev/null 2>&1 \
    && nichtok "PR-Text-Prüfer erkennt die leere Vorlage" || ok "PR-Text-Prüfer erkennt die leere Vorlage"
grep -q 'PR-Text prüfen' "$pdir/.github/workflows/tests.yml" \
    && ok "tests.yml prüft den PR-Text" || nichtok "tests.yml prüft den PR-Text"

sed -n '/"deny"/,/\]/p' "$pdir/.claude/settings.json" | grep -q '"Read(.env)"' \
    && ok "settings.json sperrt .env für Sessions (im deny-Block)" || nichtok "settings.json sperrt .env für Sessions (im deny-Block)"
grep -q 'Wegwerfprobe des Bootstraps' "$pdir/README.md" \
    && ok "README.md trägt den Zweck" || nichtok "README.md trägt den Zweck"
grep -q '@musterorg' "$pdir/.github/CODEOWNERS" \
    && ok "CODEOWNERS trägt den Eigentümer" || nichtok "CODEOWNERS trägt den Eigentümer"
grep -q 'stack: script' "$pdir/.coding-standard" \
    && ok "Markerdatei nennt den Stack" || nichtok "Markerdatei nennt den Stack"

anzahl="$(git -C "$pdir" rev-list --count HEAD 2>/dev/null || echo 0)"
[ "$anzahl" = "1" ] && ok "genau ein Commit" || nichtok "genau ein Commit (gezählt: $anzahl)"
git -C "$pdir" log -1 --pretty=%s | grep -q 'Projektgerüst nach Firmenstandard' \
    && ok "Commit-Betreff nach Standard" || nichtok "Commit-Betreff nach Standard"
[ -z "$(git -C "$pdir" status --porcelain)" ] \
    && ok "Arbeitsbaum sauber" || nichtok "Arbeitsbaum sauber"
git -C "$pdir" ls-files --error-unmatch .env >/dev/null 2>&1 \
    && nichtok "keine .env im Repo" || ok "keine .env im Repo"
# Unter Windows (core.fileMode=false) kommt das Bit nur über den Index ins Repo.
[ "$(git -C "$pdir" ls-files -s scripts/beispiel.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: scripts/beispiel.sh" \
    || nichtok "Ausführbar-Bit im Index: scripts/beispiel.sh"
[ "$(git -C "$pdir" ls-files -s .githooks/pre-commit | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: .githooks/pre-commit" \
    || nichtok "Ausführbar-Bit im Index: .githooks/pre-commit"
[ "$(git -C "$pdir" config core.hooksPath)" = ".githooks" ] \
    && ok "core.hooksPath zeigt auf .githooks" || nichtok "core.hooksPath zeigt auf .githooks"

hook_stacks "$pdir" | grep -q 'Stack erkannt: script' \
    && ok "Hook erkennt den Stack script" || nichtok "Hook erkennt den Stack script"

bash "$pdir/tests/test_beispiel_sh.sh" >/dev/null 2>&1 \
    && ok "Beispiel-Shelltest läuft im neuen Projekt" \
    || nichtok "Beispiel-Shelltest läuft im neuen Projekt"
# scripts/check.sh: grün, wenn die Werkzeuge da sind — sonst rot, und zwar nur wegen fehlender
# Werkzeuge: Die Schlusszeile „Rot: nicht alle Prüfungen konnten laufen“ erreicht nur ein Lauf,
# in dem alles Laufbare grün war (ein echter Befund bricht vorher ab). Python wie in check.sh.
ausgabe="$(cd "$pdir" && bash scripts/check.sh 2>&1)" && status=0 || status=$?
py="$(command -v python || command -v python3 || true)"
if command -v shellcheck >/dev/null 2>&1 && [ -n "$py" ] && "$py" -m ruff --version >/dev/null 2>&1 && "$py" -m pytest --version >/dev/null 2>&1; then
    [ "$status" -eq 0 ] && ok "scripts/check.sh läuft grün im neuen Projekt" \
        || nichtok "scripts/check.sh läuft grün im neuen Projekt: $ausgabe"
else
    { [ "$status" -ne 0 ] && printf '%s\n' "$ausgabe" | grep -q '^Rot: nicht alle Prüfungen konnten laufen'; } \
        && ok "scripts/check.sh: rot nur wegen fehlender Werkzeuge, alles Laufbare grün" \
        || nichtok "scripts/check.sh: rot nur wegen fehlender Werkzeuge (Status $status): $ausgabe"
fi
probe_komplexitaet "$pdir" ruff
probe_vscode "$pdir"
# Ohne Git-Repo kein stilles Grün: check.sh wechselt in seinen eigenen Projektordner, deshalb
# eine Kopie in einen losen Ordner legen; die Meldung muss den Grund nennen.
mkdir -p "$tmp/losgeloest/scripts" && cp "$pdir/scripts/check.sh" "$tmp/losgeloest/scripts/"
(bash "$tmp/losgeloest/scripts/check.sh" 2>&1 | grep -q 'kein Git-Repo') \
    && ok "scripts/check.sh verweigert außerhalb eines Git-Repos" || nichtok "scripts/check.sh verweigert außerhalb eines Git-Repos"

# Der pre-commit-Hook: geprüft wird seine Logik mit einer Attrappe an Stelle von gitleaks,
# nicht der Scanner selbst. Ein Treffer (Attrappe endet mit 1) muss den Commit über
# core.hooksPath wirklich stoppen; ohne gitleaks warnt der Hook nur und lässt durch.
attrappe="$tmp/attrappe-treffer"; mkdir -p "$attrappe" "$tmp/attrappe-leer"
printf '#!%s\nexit 1\n' "$BASH" > "$attrappe/gitleaks"; chmod +x "$attrappe/gitleaks"
ausgabe="$(cd "$pdir" && PATH="$attrappe:$PATH" bash .githooks/pre-commit 2>&1)"; status=$?
[ "$status" -eq 1 ] && grep -q '\.gitleaks\.toml' <<<"$ausgabe" && grep -q -- '--no-verify' <<<"$ausgabe" \
    && ok "Hook: Treffer → Exit 1 mit Hinweis auf .gitleaks.toml und --no-verify" \
    || nichtok "Hook: Treffer → Exit 1 mit Hinweis auf .gitleaks.toml und --no-verify (Status $status)"
# Leerer PATH: bash muss dann absolut aufgerufen werden, sonst findet die Shell schon bash nicht.
ausgabe="$(cd "$pdir" && PATH="$tmp/attrappe-leer" "$BASH" .githooks/pre-commit 2>&1)"; status=$?
[ "$status" -eq 0 ] && grep -q 'gitleaks fehlt' <<<"$ausgabe" \
    && ok "Hook: ohne gitleaks nur Warnung, Exit 0" \
    || nichtok "Hook: ohne gitleaks nur Warnung, Exit 0 (Status $status)"
printf 'Probe\n' > "$pdir/probe.txt"
git -C "$pdir" add probe.txt
(cd "$pdir" && PATH="$attrappe:$PATH" git commit -q -m "Probe: muss scheitern") >/dev/null 2>&1
[ "$(git -C "$pdir" rev-list --count HEAD)" = "1" ] \
    && ok "Hook stoppt den Commit über core.hooksPath" \
    || nichtok "Hook stoppt den Commit über core.hooksPath"

# --------------------------------------------- Bericht mit GitHub (gh-Attrappe)
echo
echo "== Bericht: Claude-Durchsicht nur nennen, was fehlt"

# Die Attrappe antwortet wie das echte gh, auch im Fehlerfall: Fehlertext auf stdout, Exit 1.
# Genau daran hielt der erste Entwurf am 2026-09-29 ein fehlendes Org-Secret für vorhanden.
# SECRET, SCHALTER und APP steuern die drei Antworten einzeln, damit „nur das Fehlende nennen“
# prüfbar ist; APP=fehler steht für ein Mitglied ohne Inhaberrechte.
attrappe="$tmp/attrappe-gh"; mkdir -p "$attrappe"
cat > "$attrappe/gh" <<EOF
#!$BASH
fehlt() { printf '{"message":"Not Found","status":"404"}'; exit 1; }
case "\$1 \$2" in
    "auth status"|"repo create") exit 0 ;;
    "repo view") exit 1 ;;
    "api user") echo tester ;;
    "api orgs/musterorg") echo '{}' ;;
    "api orgs/musterorg/installations"*) case "\$APP" in all|selected) echo "\$APP" ;; *) fehlt ;; esac ;;
    "api repos/"*"/actions/organization-secrets"*) [ "\$SECRET" = ja ] && echo CLAUDE_CODE_OAUTH_TOKEN || fehlt ;;
    "api repos/"*"/actions/organization-variables"*) [ "\$SCHALTER" = ja ] && echo true || fehlt ;;
    *) echo "gh-Attrappe: unerwarteter Aufruf: \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$attrappe/gh"

bericht() { # <name> <SECRET> <SCHALTER> <APP> — legt ein Projekt gegen die Attrappe an
    PATH="$attrappe:$PATH" SECRET="$2" SCHALTER="$3" APP="$4" lauf 0 "Projekt mit GitHub entsteht ($1)" \
        --name "$1" --stack script --owner musterorg \
        --purpose "Wegwerfprobe des Berichts." --dir "$tmp/$1"
}
bericht_nennt() { # <fall> <ja|nein> <text>
    if grep -qF -- "$3" <<<"$LETZTE_AUSGABE"; then [ "$2" = ja ]; else [ "$2" = nein ]; fi \
        && ok "Bericht $1: $([ "$2" = ja ] || echo 'nicht ')$3" \
        || nichtok "Bericht $1: $([ "$2" = ja ] || echo 'nicht ')$3"
}

bericht probe-org ja ja all
bericht_nennt "Org hält alles" ja 'Claude-Durchsicht der Pull Requests: nichts zu tun'
for text in 'setup-token' 'gh secret set' 'gh variable set' 'apps/claude'; do
    bericht_nennt "Org hält alles" nein "$text"
done

bericht probe-eigen nein nein fehler
for text in "NICHT über '!'" 'claude setup-token' \
            'gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo musterorg/probe-eigen' \
            'gh variable set CLAUDE_REVIEW_ENABLED --body true --repo musterorg/probe-eigen' \
            "GitHub-App 'Claude': nicht prüfbar"; do
    bericht_nennt "Org hält nichts, App nicht prüfbar" ja "$text"
done

bericht probe-mitglied ja ja fehler
bericht_nennt "Mitglied ohne Inhaberrechte" ja "GitHub-App 'Claude': nicht prüfbar"
for text in 'nichts zu tun' 'setup-token' 'gh secret set' 'gh variable set'; do
    bericht_nennt "Mitglied ohne Inhaberrechte" nein "$text"
done

bericht probe-misch ja nein selected
bericht_nennt "nur Schalter und App fehlen" ja 'gh variable set CLAUDE_REVIEW_ENABLED --body true --repo musterorg/probe-misch'
bericht_nennt "nur Schalter und App fehlen" ja "GitHub-App 'Claude' für musterorg/probe-misch freigeben"
for text in 'setup-token' 'gh secret set' 'nicht prüfbar' 'nichts zu tun'; do
    bericht_nennt "nur Schalter und App fehlen" nein "$text"
done

# --------------------------------------------------------------- Probe fastapi
echo
echo "== Probe: Stack fastapi (mit Umgebung und Prüfungen)"

pdir="$tmp/probe-fastapi"
lauf 0 "Projekt entsteht, Prüfungen grün" \
    --name probe-fastapi --stack fastapi --owner musterorg \
    --purpose "Wegwerfprobe des Bootstraps." --dir "$pdir" --no-github

for datei in CLAUDE.md README.md Dockerfile compose.yaml compose.build.yaml \
             .env.example pyproject.toml requirements.txt requirements-dev.txt \
             app/main.py app/settings.py app/schemas.py app/security.txt SECURITY.md docs/datenschutz.md \
             app/modules/beispiel/router.py app/modules/beispiel/service.py \
             app/modules/beispiel/schemas.py \
             tests/conftest.py tests/test_health.py tests/test_settings.py tests/test_security_txt.py \
             deploy/install.sh deploy/update.sh deploy/backup.sh deploy/dev.sh compose.dev.yaml \
             deploy/smoke.sh deploy/smoke.txt deploy/container-test.sh scripts/komplexitaet-pruefen.sh scripts/konfig-pruefen.sh scripts/lizenzen-pruefen.sh \
             .vscode/settings.json .vscode/extensions.json .vscode/tasks.json \
             scripts/release-notes.sh scripts/check.sh \
             .github/workflows/tests.yml .github/workflows/release.yml .github/workflows/nightly.yml; do
    [ -f "$pdir/$datei" ] && ok "vorhanden: $datei" || nichtok "fehlt: $datei"
done

(cd "$pdir" && bash deploy/smoke.sh --dry-run) | grep -q '^/healthz .*Status 200' \
    && ok "deploy/smoke.sh --dry-run listet die Routen" || nichtok "deploy/smoke.sh --dry-run listet die Routen"
[ "$(git -C "$pdir" ls-files -s deploy/smoke.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/smoke.sh" || nichtok "Ausführbar-Bit im Index: deploy/smoke.sh"
[ "$(git -C "$pdir" ls-files -s deploy/container-test.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/container-test.sh" || nichtok "Ausführbar-Bit im Index: deploy/container-test.sh"
{ grep -q '^RUN setcap -r ' "$pdir/Dockerfile" || ! grep -q 'frankenphp\|FROM caddy' "$pdir/Dockerfile"; } \
    && ok "Dockerfile: File-Capability des Servers entfernt (sonst kein Start mit cap_drop: ALL)" \
    || nichtok "Dockerfile: File-Capability des Servers entfernt (sonst kein Start mit cap_drop: ALL)"
{ ! grep -q -- '--chown=' "$pdir/Dockerfile" && ! grep -qE 'chown .*(/app|/srv)( |$)' "$pdir/Dockerfile"; } \
    && ok "Dockerfile: der Code gehört root (kein chown auf /app oder /srv)" \
    || nichtok "Dockerfile: der Code gehört root (kein chown auf /app oder /srv)"
grep -rlE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$pdir" --exclude-dir=.venv >/dev/null 2>&1 \
    && nichtok "keine unersetzten Platzhalter" \
    || ok "keine unersetzten Platzhalter"
# Erste Datenzeile der Befehlstabelle (nach Kopf und Trennlinie) ist der eine Prüfbefehl.
awk '/^## Befehle/{f=1;next} f&&/^\|/&&!/^\| Zweck/&&!/^\| *-/{print;exit}' "$pdir/CLAUDE.md" | grep -q 'Alles prüfen' \
    && ok "CLAUDE.md nennt den Prüfbefehl zuerst" || nichtok "CLAUDE.md nennt den Prüfbefehl zuerst"

grep -q 'env_prefix="FASTAPI_"' "$pdir/app/settings.py" \
    && ok "ENV-Präfix abgeleitet (FASTAPI_)" || nichtok "ENV-Präfix abgeleitet (FASTAPI_)"
grep -q 'Datenbank: PostgreSQL 18\.' "$pdir/CLAUDE.md" \
    && ok "CLAUDE.md nennt die Zieldatenbank aus stack.conf (PostgreSQL 18)" \
    || nichtok "CLAUDE.md nennt die Zieldatenbank aus stack.conf (PostgreSQL 18)"
grep -q 'ghcr.io/musterorg/probe-fastapi' "$pdir/compose.yaml" \
    && ok "compose.yaml zeigt auf das richtige Abbild" \
    || nichtok "compose.yaml zeigt auf das richtige Abbild"
# Softwarestückliste: aus dem gebauten Abbild (Digest), als CycloneDX, am Release — die Action
# per Commit festgenagelt wie alle anderen.
grep -qE 'uses: anchore/sbom-action@[0-9a-f]{40} ' "$pdir/.github/workflows/release.yml" \
    && grep -qF 'echo "image=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_OUTPUT"' "$pdir/.github/workflows/release.yml" \
    && grep -q 'image: ${{ steps.version.outputs.image }}@${{ steps.build.outputs.digest }}' "$pdir/.github/workflows/release.yml" \
    && grep -q 'format: cyclonedx-json' "$pdir/.github/workflows/release.yml" \
    && grep -q 'gh release upload "$TAG" "sbom-${VERSION}.cdx.json" --clobber' "$pdir/.github/workflows/release.yml" \
    && ok "release.yml: Softwarestückliste des Abbilds (CycloneDX) am Release" \
    || nichtok "release.yml: Softwarestückliste des Abbilds (CycloneDX) am Release"
# Datenbank ist PostgreSQL (Kern): Dienst db im internen Netz, die App wartet auf ihn, die
# Sicherung zieht einen Abzug, das Passwort bleibt im Schema leer.
grep -q 'image: postgres:18-alpine' "$pdir/compose.yaml" \
    && grep -q 'condition: service_healthy' "$pdir/compose.yaml" \
    && grep -q 'container_name: probe-fastapi-dev-db' "$pdir/compose.dev.yaml" \
    && ok "compose: PostgreSQL 18 als Dienst db, App wartet auf ihn, eigener Name in der Dev-Instanz" \
    || nichtok "compose: PostgreSQL 18 als Dienst db, App wartet auf ihn, eigener Name in der Dev-Instanz"
grep -q 'pg_dump -U "\$DB_USERNAME" -d "\$DB_DATABASE" -Fc' "$pdir/deploy/backup.sh" \
    && grep -q '/\*\.dump' "$pdir/deploy/update.sh" \
    && ok "deploy/backup.sh sichert die Datenbank, update.sh nennt den Abzug im Rückweg" \
    || nichtok "deploy/backup.sh sichert die Datenbank, update.sh nennt den Abzug im Rückweg"
grep -q '^DB_PASSWORD=$' "$pdir/.env.example" && grep -q '^DB_DATABASE=probe_fastapi$' "$pdir/.env.example" \
    && ok ".env.example: DB_-Schlüssel ohne Präfix, Passwort leer" \
    || nichtok ".env.example: DB_-Schlüssel ohne Präfix, Passwort leer"
probe_komplexitaet "$pdir" ruff
# Positivfall: 15 Zweige sind ein Befund — heute als WARN (Exit 0), ab 2027-01-01 rot.
{ printf 'def zu_gross(x: int) -> int:\n'; for i in $(seq 1 15); do printf '    if x == %s:\n        return %s\n' "$i" "$i"; done; printf '    return 0\n'; } > "$pdir/app/zu_gross.py"
ausgabe="$(cd "$pdir" && bash scripts/komplexitaet-pruefen.sh 2>&1)" && status=0 || status=$?
printf '%s\n' "$ausgabe" | grep -qE 'Komplexität: [1-9][0-9]* Befund' \
    && ok "scripts/komplexitaet-pruefen.sh: 15 Zweige sind ein Befund" \
    || nichtok "scripts/komplexitaet-pruefen.sh: 15 Zweige sind ein Befund (Status $status): $(printf '%s\n' "$ausgabe" | tail -2 | tr '\n' ' ')"
rm -f "$pdir/app/zu_gross.py"
probe_konfig_lizenzen "$pdir"
# Offenlegung: Das Gerüst nennt Kontakt und Ablauf; der Prüfer merkt ein abgelaufenes oder bald
# ablaufendes Expires und ein fehlendes SECURITY.md — die Sicherung wird mit der Gefahr geprüft.
grep -q '^Contact: mailto:security@cvsystems\.ai$' "$pdir/app/security.txt" \
    && grep -qE "^Expires: $(( $(date +%Y) + 1 ))-[0-9]{2}-01T00:00:00Z$" "$pdir/app/security.txt" \
    && ok "security.txt: Contact und Expires (Monatserster in einem Jahr)" \
    || nichtok "security.txt: Contact und Expires (Monatserster in einem Jahr): $(grep -E '^(Contact|Expires):' "$pdir/app/security.txt" | tr '\n' ' ')"
(cd "$pdir" && bash scripts/konfig-pruefen.sh 2>&1) | grep -q '^Hinweis SECURITY.md: Supportzeitraum oder unterstützte Fassungen noch festzulegen' \
    && ok "konfig-pruefen.sh: offener Supportzeitraum ist ein Hinweis" \
    || nichtok "konfig-pruefen.sh: offener Supportzeitraum ist ein Hinweis"
cp "$pdir/app/security.txt" "$tmp/security.txt.orig"
printf 'Contact: mailto:security@example.invalid\nExpires: 2020-01-01T00:00:00Z\n' > "$pdir/app/security.txt"
ausgabe="$(cd "$pdir" && bash scripts/konfig-pruefen.sh 2>&1)" && status=0 || status=$?
[ "$status" -eq 1 ] && printf '%s\n' "$ausgabe" | grep -q '^BEFUND  app/security.txt: abgelaufen am 2020-01-01' \
    && ok "konfig-pruefen.sh: abgelaufenes Expires ist ein Befund" \
    || nichtok "konfig-pruefen.sh: abgelaufenes Expires ist ein Befund (Status $status)"
# Ein Ablauf in wenigen Tagen: im selben Monat, ab dem 26. am Monatsersten des nächsten.
heute="$(date +%Y-%m-%d)"; j=$((10#${heute:0:4})); m=$((10#${heute:5:2})); t=$((10#${heute:8:2}))
if [ "$t" -le 25 ]; then t=$((t + 3)); else t=1; m=$((m + 1)); [ "$m" -le 12 ] || { m=1; j=$((j + 1)); }; fi
bald="$(printf '%04d-%02d-%02d' "$j" "$m" "$t")"
printf 'Contact: mailto:security@example.invalid\nExpires: %sT00:00:00Z\n' "$bald" > "$pdir/app/security.txt"
ausgabe="$(cd "$pdir" && bash scripts/konfig-pruefen.sh 2>&1)" && status=0 || status=$?
[ "$status" -eq 0 ] && printf '%s\n' "$ausgabe" | grep -q "^Hinweis app/security.txt: läuft am $bald ab" \
    && ok "konfig-pruefen.sh: Ablauf in wenigen Tagen ist ein Hinweis, kein Befund" \
    || nichtok "konfig-pruefen.sh: Ablauf in wenigen Tagen ist ein Hinweis, kein Befund (Status $status, $bald)"
# konfig_fall <status> <muster> <name> — ein Lauf des Prüfers gegen die gerade geschriebene Datei
konfig_fall() {
    local aus st
    aus="$(cd "$pdir" && bash scripts/konfig-pruefen.sh 2>&1)" && st=0 || st=$?
    if [ "$st" -eq "$1" ] && printf '%s\n' "$aus" | grep -q "$2"; then ok "konfig-pruefen.sh: $3"
    else nichtok "konfig-pruefen.sh: $3 (Status $st): $(printf '%s\n' "$aus" | grep -E 'BEFUND|Hinweis app' | head -2 | tr '\n' ' ')"; fi
}
printf 'Expires: 2030-01-01T00:00:00Z\n' > "$pdir/app/security.txt"
konfig_fall 1 '^BEFUND  app/security.txt: Contact fehlt' "security.txt ohne Contact ist ein Befund"
printf 'Contact: mailto:security@example.invalid\nExpires: 2030-01-01\n' > "$pdir/app/security.txt"
konfig_fall 1 'Expires fehlt oder ist kein Zeitpunkt' "Expires ohne Uhrzeit ist ein Befund"
printf 'Contact: mailto:security@example.invalid\nExpires: 2030-13-45T00:00:00Z\n' > "$pdir/app/security.txt"
konfig_fall 1 'Expires fehlt oder ist kein Zeitpunkt' "Expires mit Monat 13 ist ein Befund"
printf 'Contact: mailto:security@example.invalid\nExpires: 2030-01-01T00:00:00Z\nExpires: 2020-01-01T00:00:00Z\n' > "$pdir/app/security.txt"
konfig_fall 1 'Expires steht 2-mal da' "doppeltes Expires ist ein Befund"
printf 'Contact: mailto:security@example.invalid\nExpires: 2099-01-01T00:00:00Z\n' > "$pdir/app/security.txt"
konfig_fall 0 '^Hinweis app/security.txt: Expires am 2099-01-01 liegt mehr als ein Jahr voraus' "Expires weit voraus ist ein Hinweis"
rm -f "$pdir/app/security.txt"
konfig_fall 1 '^BEFUND  app/security.txt fehlt' "fehlende security.txt ist ein Befund"
cp "$tmp/security.txt.orig" "$pdir/app/security.txt"
# KI-Transparenz: eine ausgelieferte KI-Bibliothek ohne docs/ki-modelle.md ist ein Befund.
cp "$pdir/requirements.txt" "$tmp/requirements.txt.orig"
printf 'OpenAI>=1.0  # Probe\n' >> "$pdir/requirements.txt"
konfig_fall 1 '^BEFUND  KI-Bibliothek (openai) ohne docs/ki-modelle.md' "KI-Bibliothek ohne docs/ki-modelle.md ist ein Befund"
cp "$root/templates/dokumente/ki-modelle.md" "$pdir/docs/ki-modelle.md"
konfig_fall 0 '^ok      KI-Bibliothek (openai) und docs/ki-modelle.md' "KI-Bibliothek mit docs/ki-modelle.md ist sauber"
rm -f "$pdir/docs/ki-modelle.md"; cp "$tmp/requirements.txt.orig" "$pdir/requirements.txt"
# Nur Ausgeliefertes zählt: Entwicklungsabhängigkeiten bleiben sauber, auch hinter einem leeren
# oder einzeiligen dependencies-Block; ein einzeiliger Block mit KI-Bibliothek ist ein Befund.
cp "$pdir/requirements-dev.txt" "$tmp/requirements-dev.txt.orig"
printf 'openai\n' >> "$pdir/requirements-dev.txt"
printf '{\n  "dependencies": {},\n  "devDependencies": { "openai": "^4" }\n}\n' > "$pdir/package.json"
konfig_fall 0 '^Konfiguration: sauber' "KI-Bibliothek nur als Entwicklungsabhängigkeit ist sauber"
printf '{ "dependencies": { "react": "^19", "@anthropic-ai/sdk": "^1" } }\n' > "$pdir/package.json"
konfig_fall 1 '^BEFUND  KI-Bibliothek (@anthropic-ai/sdk) ohne' "einzeiliger dependencies-Block mit KI-Bibliothek ist ein Befund"
rm -f "$pdir/package.json"; cp "$tmp/requirements-dev.txt.orig" "$pdir/requirements-dev.txt"
mv "$pdir/SECURITY.md" "$tmp/SECURITY.md.orig"
ausgabe="$(cd "$pdir" && bash scripts/konfig-pruefen.sh 2>&1)" && status=0 || status=$?
[ "$status" -eq 1 ] && printf '%s\n' "$ausgabe" | grep -q '^BEFUND  SECURITY.md fehlt' \
    && ok "konfig-pruefen.sh: fehlendes SECURITY.md ist ein Befund" \
    || nichtok "konfig-pruefen.sh: fehlendes SECURITY.md ist ein Befund (Status $status)"
mv "$tmp/SECURITY.md.orig" "$pdir/SECURITY.md"
probe_vscode "$pdir"
# Verbund gegen docker compose prüfen, wo es das gibt (CI-Läufer): gültig mit gesetzten
# Pflichtvariablen, verweigert ohne sie (`:?`). Die .env dafür kommt aus .env.example und
# verschwindet wieder — sie gehört nicht ins Repo.
if docker compose version >/dev/null 2>&1; then
    cp "$pdir/.env.example" "$pdir/.env"
    (cd "$pdir" && APP_VERSION=probe DB_DATABASE=p DB_USERNAME=p DB_PASSWORD=p DB_NAME=p DB_USER=p \
        docker compose -f compose.yaml config -q) \
        && ok "compose.yaml ist gültig (docker compose config)" \
        || nichtok "compose.yaml ist gültig (docker compose config)"
    (cd "$pdir" && docker compose --env-file /dev/null -f compose.yaml config -q >/dev/null 2>&1) \
        && nichtok "compose.yaml verweigert den Start ohne Pflichtvariablen" \
        || ok "compose.yaml verweigert den Start ohne Pflichtvariablen"
    # Die .env aus dem Schema hat DB_PASSWORD leer — genau das muss der Dienst db abweisen.
    ausgabe="$(cd "$pdir" && APP_VERSION=probe docker compose -f compose.yaml config -q 2>&1)" \
        && nichtok "compose.yaml verweigert den Start mit leerem DB_PASSWORD" \
        || { printf '%s' "$ausgabe" | grep -q 'DB_PASSWORD fehlt' \
            && ok "compose.yaml verweigert den Start mit leerem DB_PASSWORD" \
            || nichtok "compose.yaml verweigert den Start mit leerem DB_PASSWORD: $ausgabe"; }
    rm -f "$pdir/.env"
else
    echo "skip   compose.yaml gegen docker compose (kein docker auf diesem Rechner)"
fi
[ -f "$pdir/.coding-standard" ] \
    && nichtok "fastapi braucht keine Markerdatei" || ok "fastapi braucht keine Markerdatei"

anzahl="$(git -C "$pdir" rev-list --count HEAD 2>/dev/null || echo 0)"
[ "$anzahl" = "1" ] && ok "genau ein Commit" || nichtok "genau ein Commit (gezählt: $anzahl)"
git -C "$pdir" ls-files | grep -q '^\.venv/' \
    && nichtok "die virtuelle Umgebung bleibt draußen" \
    || ok "die virtuelle Umgebung bleibt draußen"
[ "$(git -C "$pdir" ls-files -s deploy/update.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/update.sh" \
    || nichtok "Ausführbar-Bit im Index: deploy/update.sh"
[ "$(git -C "$pdir" ls-files -s deploy/dev.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/dev.sh" \
    || nichtok "Ausführbar-Bit im Index: deploy/dev.sh"
grep -q '^APP_DOMAIN=' "$pdir/.env.example" \
    && ok "APP_DOMAIN in .env.example (Anschluss an den Edge)" \
    || nichtok "APP_DOMAIN in .env.example (Anschluss an den Edge)"

hook_stacks "$pdir" | grep -q 'Stack erkannt: fastapi' \
    && ok "Hook erkennt den Stack fastapi" || nichtok "Hook erkennt den Stack fastapi"

# ----------------------------------------------------------------- Probe astro
echo
echo "== Probe: Stack astro (mit npm install, Bau und Tests)"

# container-test.sh fasst keine vorhandene .env an und kennt nur prod und dev — beides bricht
# vor jedem docker-Aufruf ab (Probe: FastAPI).
pdir="$tmp/probe-fastapi"
env_da=0; [ -e "$pdir/.env" ] && env_da=1
[ "$env_da" -eq 1 ] || : > "$pdir/.env"
out="$(cd "$pdir" && bash deploy/container-test.sh 2>&1)"; rc=$?
[ "$env_da" -eq 1 ] || rm -f "$pdir/.env"
[ "$rc" -ne 0 ] && grep -q '.env ist vorhanden' <<<"$out" \
    && ok "container-test.sh verweigert bei vorhandener .env" \
    || nichtok "container-test.sh verweigert bei vorhandener .env (rc=$rc)"
out="$(cd "$pdir" && bash deploy/container-test.sh gibt-es-nicht 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q 'Unbekannte Variante' <<<"$out" \
    && ok "container-test.sh verweigert eine unbekannte Variante" \
    || nichtok "container-test.sh verweigert eine unbekannte Variante (rc=$rc)"

pdir="$tmp/probe-astro"
lauf 0 "Projekt entsteht, Prüfungen grün" \
    --name probe-astro --stack astro --owner musterorg \
    --purpose "Wegwerfprobe des Bootstraps." --dir "$pdir" --no-github

for datei in CLAUDE.md README.md Dockerfile compose.yaml compose.build.yaml \
             .env.example package.json package-lock.json astro.config.mjs \
             tsconfig.json \
             src/layouts/Base.astro src/pages/index.astro src/pages/404.astro \
             src/styles/global.css public/robots.txt public/favicon.svg \
             public/.well-known/security.txt dist/.well-known/security.txt SECURITY.md \
             tests/build.test.mjs .claude/rules/inhalt.md .claude/rules/tests.md docker/Caddyfile \
             tests/e2e/playwright.config.ts tests/e2e/smoke.spec.ts tests/e2e/sweep.spec.ts tests/e2e/tsconfig.json \
             tests/e2e/barrierefreiheit.spec.ts \
             deploy/install.sh deploy/update.sh deploy/backup.sh deploy/dev.sh compose.dev.yaml \
             deploy/smoke.sh deploy/smoke.txt deploy/container-test.sh scripts/komplexitaet-pruefen.sh scripts/konfig-pruefen.sh scripts/lizenzen-pruefen.sh \
             .vscode/settings.json .vscode/extensions.json .vscode/tasks.json \
             scripts/release-notes.sh \
             .github/workflows/tests.yml .github/workflows/release.yml \
             .github/dependabot.yml \
             node_modules/@axe-core/playwright/package.json \
             dist/index.html dist/404.html dist/sitemap-index.xml; do
    [ -f "$pdir/$datei" ] && ok "vorhanden: $datei" || nichtok "fehlt: $datei"
done
# Barrierefreiheit: vorhanden, aber aus, bis das Projekt sie einschaltet (Vorgabe des Inhabers).
# Dass die Spezifikation mit dem Modul übersetzt, belegt `check:types` (tsc -p tests/e2e) im
# Prüflauf des Gerüsts.
grep -q '^const EINGESCHALTET = false;$' "$pdir/tests/e2e/barrierefreiheit.spec.ts" \
    && grep -q "withTags(\['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'\])" "$pdir/tests/e2e/barrierefreiheit.spec.ts" \
    && ok "barrierefreiheit.spec.ts: WCAG 2.1 AA, standardmäßig aus" \
    || nichtok "barrierefreiheit.spec.ts: WCAG 2.1 AA, standardmäßig aus"
# Laravel bekommt dieselbe Datei (die Suite baut kein Laravel-Gerüst): Vorlagen gleich halten.
cmp -s "$root/templates/astro/dateien/tests/e2e/barrierefreiheit.spec.ts" \
       "$root/templates/laravel/dateien/tests/e2e/barrierefreiheit.spec.ts" \
    && ok "barrierefreiheit.spec.ts: Astro und Laravel gleich" \
    || nichtok "barrierefreiheit.spec.ts: Astro und Laravel gleich"

grep -rlE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$pdir" \
    --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.astro >/dev/null 2>&1 \
    && nichtok "keine unersetzten Platzhalter" \
    || ok "keine unersetzten Platzhalter"
# Erste Datenzeile der Befehlstabelle (nach Kopf und Trennlinie) ist der eine Prüfbefehl.
awk '/^## Befehle/{f=1;next} f&&/^\|/&&!/^\| Zweck/&&!/^\| *-/{print;exit}' "$pdir/CLAUDE.md" | grep -q 'Alles prüfen' \
    && ok "CLAUDE.md nennt den Prüfbefehl zuerst" || nichtok "CLAUDE.md nennt den Prüfbefehl zuerst"

grep -q 'ghcr.io/musterorg/probe-astro' "$pdir/compose.yaml" \
    && ok "compose.yaml zeigt auf das richtige Abbild" \
    || nichtok "compose.yaml zeigt auf das richtige Abbild"
probe_komplexitaet "$pdir"
probe_konfig_lizenzen "$pdir"
probe_vscode "$pdir"
(cd "$pdir" && bash deploy/smoke.sh --dry-run) | grep -q '^/healthz .*Status 200' \
    && ok "deploy/smoke.sh --dry-run listet die Routen" || nichtok "deploy/smoke.sh --dry-run listet die Routen"
[ "$(git -C "$pdir" ls-files -s deploy/smoke.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/smoke.sh" || nichtok "Ausführbar-Bit im Index: deploy/smoke.sh"
[ "$(git -C "$pdir" ls-files -s deploy/container-test.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/container-test.sh" || nichtok "Ausführbar-Bit im Index: deploy/container-test.sh"
{ grep -q '^RUN setcap -r ' "$pdir/Dockerfile" || ! grep -q 'frankenphp\|FROM caddy' "$pdir/Dockerfile"; } \
    && ok "Dockerfile: File-Capability des Servers entfernt (sonst kein Start mit cap_drop: ALL)" \
    || nichtok "Dockerfile: File-Capability des Servers entfernt (sonst kein Start mit cap_drop: ALL)"
{ ! grep -q -- '--chown=' "$pdir/Dockerfile" && ! grep -qE 'chown .*(/app|/srv)( |$)' "$pdir/Dockerfile"; } \
    && ok "Dockerfile: der Code gehört root (kein chown auf /app oder /srv)" \
    || nichtok "Dockerfile: der Code gehört root (kein chown auf /app oder /srv)"

# Verbund gegen docker compose prüfen, wo es das gibt (CI-Läufer): gültig mit gesetzten
# Pflichtvariablen, verweigert ohne sie (`:?`). Die .env dafür kommt aus .env.example und
# verschwindet wieder — sie gehört nicht ins Repo.
if docker compose version >/dev/null 2>&1; then
    cp "$pdir/.env.example" "$pdir/.env"
    (cd "$pdir" && APP_VERSION=probe DB_DATABASE=p DB_USERNAME=p DB_PASSWORD=p DB_NAME=p DB_USER=p \
        docker compose -f compose.yaml config -q) \
        && ok "compose.yaml ist gültig (docker compose config)" \
        || nichtok "compose.yaml ist gültig (docker compose config)"
    (cd "$pdir" && docker compose --env-file /dev/null -f compose.yaml config -q >/dev/null 2>&1) \
        && nichtok "compose.yaml verweigert den Start ohne Pflichtvariablen" \
        || ok "compose.yaml verweigert den Start ohne Pflichtvariablen"
    rm -f "$pdir/.env"
else
    echo "skip   compose.yaml gegen docker compose (kein docker auf diesem Rechner)"
fi
grep -q 'https://probe-astro.invalid' "$pdir/astro.config.mjs" \
    && ok "astro.config.mjs trägt die Platzhalter-Domain" \
    || nichtok "astro.config.mjs trägt die Platzhalter-Domain"
[ -f "$pdir/.coding-standard" ] \
    && nichtok "astro braucht keine Markerdatei" || ok "astro braucht keine Markerdatei"
grep -q 'site' "$pdir/.projekt-neu-nacharbeit" 2>/dev/null \
    && ok "Nacharbeit nennt site" || nichtok "Nacharbeit nennt site"

anzahl="$(git -C "$pdir" rev-list --count HEAD 2>/dev/null || echo 0)"
[ "$anzahl" = "1" ] && ok "genau ein Commit" || nichtok "genau ein Commit (gezählt: $anzahl)"
git -C "$pdir" ls-files | grep -qE '^(node_modules|dist|\.astro)/' \
    && nichtok "node_modules, dist und .astro bleiben draußen" \
    || ok "node_modules, dist und .astro bleiben draußen"
git -C "$pdir" ls-files --error-unmatch .projekt-neu-nacharbeit >/dev/null 2>&1 \
    && nichtok "Nacharbeit-Datei bleibt draußen" || ok "Nacharbeit-Datei bleibt draußen"
git -C "$pdir" ls-files --error-unmatch package-lock.json >/dev/null 2>&1 \
    && ok "package-lock.json ist im Repo" || nichtok "package-lock.json ist im Repo"
[ "$(git -C "$pdir" ls-files -s deploy/update.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/update.sh" \
    || nichtok "Ausführbar-Bit im Index: deploy/update.sh"
[ "$(git -C "$pdir" ls-files -s deploy/dev.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/dev.sh" \
    || nichtok "Ausführbar-Bit im Index: deploy/dev.sh"
grep -q '^APP_DOMAIN=' "$pdir/.env.example" \
    && ok "APP_DOMAIN in .env.example (Anschluss an den Edge)" \
    || nichtok "APP_DOMAIN in .env.example (Anschluss an den Edge)"

hook_stacks "$pdir" | grep -q 'Stack erkannt: astro' \
    && ok "Hook erkennt den Stack astro" || nichtok "Hook erkennt den Stack astro"

grep -q 'Wegwerfprobe des Bootstraps' "$pdir/dist/index.html" \
    && ok "dist/index.html trägt den Zweck" || nichtok "dist/index.html trägt den Zweck"
grep -q 'lang="de"' "$pdir/dist/index.html" \
    && ok 'dist/index.html ist Deutsch (lang="de")' || nichtok 'dist/index.html ist Deutsch (lang="de")'

# ------------------------------------------------------------- Probe wordpress
echo
echo "== Probe: Stack wordpress (mit composer install und composer check)"

pdir="$tmp/probe-wordpress"
lauf 0 "Projekt entsteht, Prüfungen grün" \
    --name probe-wordpress --stack wordpress --owner musterorg \
    --purpose "Wegwerfprobe des Bootstraps." --dir "$pdir" --no-github

for datei in CLAUDE.md README.md Dockerfile compose.yaml compose.build.yaml \
             compose.dev.yaml .env.example composer.json composer.lock wp-cli.yml phpmd.xml \
             phpcs.xml phpstan.neon \
             config/application.php config/environments/development.php docs/datenschutz.md \
             web/index.php web/wp-config.php web/wp/wp-settings.php \
             web/.well-known/security.txt SECURITY.md \
             web/app/mu-plugins/firmenstandard.php \
             web/app/themes/site/style.css web/app/themes/site/theme.json \
             web/app/themes/site/functions.php \
             web/app/themes/site/templates/index.html \
             web/app/themes/site/templates/singular.html \
             web/app/themes/site/templates/404.html \
             web/app/themes/site/parts/header.html \
             web/app/themes/site/parts/footer.html \
             tests/pruefe-struktur.php .claude/rules/site.md .claude/rules/tests.md \
             docker/Caddyfile docker/php.ini docker/php.dev.ini docker/entrypoint.sh \
             docker/sprachpakete.php \
             deploy/install.sh deploy/update.sh deploy/backup.sh deploy/dev.sh compose.dev.yaml \
             deploy/smoke.sh deploy/smoke.txt deploy/container-test.sh scripts/komplexitaet-pruefen.sh scripts/konfig-pruefen.sh scripts/lizenzen-pruefen.sh \
             .vscode/settings.json .vscode/extensions.json .vscode/tasks.json \
             scripts/release-notes.sh \
             .github/workflows/tests.yml .github/workflows/release.yml \
             .github/dependabot.yml; do
    [ -f "$pdir/$datei" ] && ok "vorhanden: $datei" || nichtok "fehlt: $datei"
done

grep -rlE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$pdir" \
    --exclude-dir=vendor --exclude-dir=wp >/dev/null 2>&1 \
    && nichtok "keine unersetzten Platzhalter" \
    || ok "keine unersetzten Platzhalter"
# Erste Datenzeile der Befehlstabelle (nach Kopf und Trennlinie) ist der eine Prüfbefehl.
awk '/^## Befehle/{f=1;next} f&&/^\|/&&!/^\| Zweck/&&!/^\| *-/{print;exit}' "$pdir/CLAUDE.md" | grep -q 'Alles prüfen' \
    && ok "CLAUDE.md nennt den Prüfbefehl zuerst" || nichtok "CLAUDE.md nennt den Prüfbefehl zuerst"

grep -q 'ghcr.io/musterorg/probe-wordpress' "$pdir/compose.yaml" \
    && ok "compose.yaml zeigt auf das richtige Abbild" \
    || nichtok "compose.yaml zeigt auf das richtige Abbild"
probe_komplexitaet "$pdir" PHPMD
probe_konfig_lizenzen "$pdir"
probe_vscode "$pdir"
(cd "$pdir" && bash deploy/smoke.sh --dry-run) | grep -q '^/healthz .*Status 200' \
    && ok "deploy/smoke.sh --dry-run listet die Routen" || nichtok "deploy/smoke.sh --dry-run listet die Routen"
[ "$(git -C "$pdir" ls-files -s deploy/smoke.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/smoke.sh" || nichtok "Ausführbar-Bit im Index: deploy/smoke.sh"
[ "$(git -C "$pdir" ls-files -s deploy/container-test.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/container-test.sh" || nichtok "Ausführbar-Bit im Index: deploy/container-test.sh"
{ grep -q '^RUN setcap -r ' "$pdir/Dockerfile" || ! grep -q 'frankenphp\|FROM caddy' "$pdir/Dockerfile"; } \
    && ok "Dockerfile: File-Capability des Servers entfernt (sonst kein Start mit cap_drop: ALL)" \
    || nichtok "Dockerfile: File-Capability des Servers entfernt (sonst kein Start mit cap_drop: ALL)"
{ ! grep -q -- '--chown=' "$pdir/Dockerfile" && ! grep -qE 'chown .*(/app|/srv)( |$)' "$pdir/Dockerfile"; } \
    && ok "Dockerfile: der Code gehört root (kein chown auf /app oder /srv)" \
    || nichtok "Dockerfile: der Code gehört root (kein chown auf /app oder /srv)"

# Verbund gegen docker compose prüfen, wo es das gibt (CI-Läufer): gültig mit gesetzten
# Pflichtvariablen, verweigert, wenn DB_PASSWORD in der .env leer bleibt (`:?`). Die .env dafür
# kommt aus .env.example und verschwindet wieder — sie gehört nicht ins Repo.
if docker compose version >/dev/null 2>&1; then
    cp "$pdir/.env.example" "$pdir/.env"
    (cd "$pdir" && APP_VERSION=probe DB_NAME=p DB_USER=p DB_PASSWORD=p \
        docker compose -f compose.yaml config -q) \
        && ok "compose.yaml ist gültig (docker compose config, Anker und cap_add)" \
        || nichtok "compose.yaml ist gültig (docker compose config, Anker und cap_add)"
    (cd "$pdir" && APP_VERSION=probe DB_NAME=p DB_USER=p docker compose -f compose.yaml config -q >/dev/null 2>&1) \
        && nichtok "compose.yaml verweigert den Start ohne DB_PASSWORD" \
        || ok "compose.yaml verweigert den Start ohne DB_PASSWORD"
    rm -f "$pdir/.env"
    # Laravel hat keine Probe (laravel new braucht Minuten): die Vorlage mit ersetzten
    # Platzhaltern durch docker compose config schicken — dieselben Konstrukte, dieselbe Prüfung.
    mkdir -p "$tmp/laravel-compose" && : > "$tmp/laravel-compose/.env"
    sed 's/{{NAME}}/probe/g; s#{{IMAGE}}#ghcr.io/musterorg/probe#g' \
        "$(dirname "${BASH_SOURCE[0]}")/../templates/laravel/dateien/compose.yaml" > "$tmp/laravel-compose/compose.yaml"
    (cd "$tmp/laravel-compose" && APP_VERSION=probe DB_DATABASE=p DB_USERNAME=p DB_PASSWORD=p \
        docker compose -f compose.yaml config -q) \
        && ok "laravel/compose.yaml ist gültig (docker compose config, Anker, tmpfs-Alias, cap_add)" \
        || nichtok "laravel/compose.yaml ist gültig (docker compose config, Anker, tmpfs-Alias, cap_add)"
    (cd "$tmp/laravel-compose" && APP_VERSION=probe DB_DATABASE=p DB_USERNAME=p docker compose -f compose.yaml config -q >/dev/null 2>&1) \
        && nichtok "laravel/compose.yaml verweigert den Start ohne DB_PASSWORD" \
        || ok "laravel/compose.yaml verweigert den Start ohne DB_PASSWORD"
else
    echo "skip   compose.yaml gegen docker compose (kein docker auf diesem Rechner)"
fi
grep -q 'https://probe-wordpress.invalid' "$pdir/.env.example" \
    && ok ".env.example trägt die Platzhalter-Domain" \
    || nichtok ".env.example trägt die Platzhalter-Domain"
grep -q 'DB_NAME=probe_wordpress' "$pdir/.env.example" \
    && ok ".env.example: Datenbankname in snake_case" \
    || nichtok ".env.example: Datenbankname in snake_case"
grep -q '^Theme Name: probe-wordpress' "$pdir/web/app/themes/site/style.css" \
    && ok "Theme trägt den Projektnamen" || nichtok "Theme trägt den Projektnamen"
[ -f "$pdir/.coding-standard" ] \
    && nichtok "wordpress braucht keine Markerdatei" || ok "wordpress braucht keine Markerdatei"
grep -q 'WP_HOME' "$pdir/.projekt-neu-nacharbeit" 2>/dev/null \
    && ok "Nacharbeit nennt WP_HOME" || nichtok "Nacharbeit nennt WP_HOME"

anzahl="$(git -C "$pdir" rev-list --count HEAD 2>/dev/null || echo 0)"
[ "$anzahl" = "1" ] && ok "genau ein Commit" || nichtok "genau ein Commit (gezählt: $anzahl)"
git -C "$pdir" ls-files | grep -qE '^(vendor|web/wp)/' \
    && nichtok "vendor und web/wp bleiben draußen" \
    || ok "vendor und web/wp bleiben draußen"
git -C "$pdir" ls-files --error-unmatch composer.lock >/dev/null 2>&1 \
    && ok "composer.lock ist im Repo" || nichtok "composer.lock ist im Repo"
git -C "$pdir" ls-files --error-unmatch web/app/themes/site/theme.json >/dev/null 2>&1 \
    && ok "das eigene Theme ist im Repo" || nichtok "das eigene Theme ist im Repo"
git -C "$pdir" ls-files --error-unmatch .projekt-neu-nacharbeit >/dev/null 2>&1 \
    && nichtok "Nacharbeit-Datei bleibt draußen" || ok "Nacharbeit-Datei bleibt draußen"
[ "$(git -C "$pdir" ls-files -s deploy/update.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/update.sh" \
    || nichtok "Ausführbar-Bit im Index: deploy/update.sh"
[ "$(git -C "$pdir" ls-files -s deploy/dev.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/dev.sh" \
    || nichtok "Ausführbar-Bit im Index: deploy/dev.sh"
grep -q '^APP_DOMAIN=' "$pdir/.env.example" \
    && ok "APP_DOMAIN in .env.example (Anschluss an den Edge)" \
    || nichtok "APP_DOMAIN in .env.example (Anschluss an den Edge)"
[ "$(git -C "$pdir" ls-files -s docker/entrypoint.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: docker/entrypoint.sh" \
    || nichtok "Ausführbar-Bit im Index: docker/entrypoint.sh"

hook_stacks "$pdir" | grep -q 'Stack erkannt: wordpress' \
    && ok "Hook erkennt den Stack wordpress" || nichtok "Hook erkennt den Stack wordpress"

# ------------------------------------------------- Laravel-Vorlage: Härtung startet
# Laravel hat keine Probe (laravel new braucht Minuten); den Start belegt vorlagen-container.yml.
# Hier die vier Stellen aus Issue #85 (Pilot, 2026-09-29), damit ein Rückfall schon im Pflicht-
# Check auffällt.
echo
echo "== Laravel-Vorlage: gehärteter Verbund (Issue #85)"
lv="$(dirname "${BASH_SOURCE[0]}")/../templates/laravel/dateien"
grep -q '^mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views$' "$lv/docker/entrypoint.sh" \
    && [ "$(grep -n '^mkdir -p storage/framework' "$lv/docker/entrypoint.sh" | cut -d: -f1)" -lt "$(grep -n '^[[:space:]]*wait_for_database$' "$lv/docker/entrypoint.sh" | head -1 | cut -d: -f1)" ] \
    && ok "entrypoint.sh legt die Laufzeitordner im tmpfs vor dem ersten artisan-Aufruf an" \
    || nichtok "entrypoint.sh legt die Laufzeitordner im tmpfs vor dem ersten artisan-Aufruf an"
grep -q 'printf .%s\\n. "$ausgabe"' "$lv/docker/entrypoint.sh" \
    && ok "entrypoint.sh zeigt beim Abbruch die Ausgabe von artisan" \
    || nichtok "entrypoint.sh zeigt beim Abbruch die Ausgabe von artisan"
grep -q '^RUN setcap -r /usr/local/bin/frankenphp$' "$lv/Dockerfile" \
    && ok "Dockerfile entfernt die File-Capability von frankenphp" \
    || nichtok "Dockerfile entfernt die File-Capability von frankenphp"
[ "$(grep -c '^USER www-data$' "$lv/Dockerfile")" -eq 1 ] && ! grep -q -- '--chown=www-data' "$lv/Dockerfile" \
    && ok "Dockerfile: Prozess als www-data, Code gehört root" \
    || nichtok "Dockerfile: Prozess als www-data, Code gehört root"
! grep -q '{' <(grep '^RUN mkdir' "$lv/Dockerfile") \
    && ok "Dockerfile: keine Klammer-Erweiterung unter /bin/sh" \
    || nichtok "Dockerfile: keine Klammer-Erweiterung unter /bin/sh"
[ "$(sed -n '/^x-app-tmpfs:/,/^$/p' "$lv/compose.yaml" | grep -c '^    - /')" -eq "$(sed -n '/^x-app-tmpfs:/,/^$/p' "$lv/compose.yaml" | grep -c ':uid=33,gid=33$')" ] \
    && ok "compose.yaml: jedes tmpfs der Anwendung gehört www-data (uid/gid 33)" \
    || nichtok "compose.yaml: jedes tmpfs der Anwendung gehört www-data (uid/gid 33)"
grep -q "INERTIA_DEVTOOLS_ENABLED: 'false'" "$lv/compose.dev.yaml" \
    && ok "compose.dev.yaml: Inertia-DevTools aus (schreiben sonst ins read_only-Dateisystem)" \
    || nichtok "compose.dev.yaml: Inertia-DevTools aus (schreiben sonst ins read_only-Dateisystem)"
cmp -s "$lv/deploy/container-test.sh" "$(dirname "${BASH_SOURCE[0]}")/../templates/fastapi/dateien/deploy/container-test.sh" \
    && cmp -s "$lv/deploy/container-test.sh" "$(dirname "${BASH_SOURCE[0]}")/../templates/astro/dateien/deploy/container-test.sh" \
    && cmp -s "$lv/deploy/container-test.sh" "$(dirname "${BASH_SOURCE[0]}")/../templates/wordpress/dateien/deploy/container-test.sh" \
    && ok "container-test.sh ist in allen vier Web-Vorlagen gleich" \
    || nichtok "container-test.sh ist in allen vier Web-Vorlagen gleich"

echo
if [ "$fehler" -eq 0 ]; then
    echo "Alle Fälle grün."
else
    echo "Fehler: $fehler"
    exit 1
fi
