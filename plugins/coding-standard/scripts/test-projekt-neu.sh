#!/usr/bin/env bash
# Prüft projekt-neu.sh: Argumentprüfung, Stack-Register und vier echte Proben.
#
#     bash plugins/coding-standard/scripts/test-projekt-neu.sh
#
# Die Proben laufen mit --no-github in einem Wegwerf-Verzeichnis; es entsteht
# kein Repository auf GitHub und nichts außerhalb von $TMPDIR. Die
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

for datei in CLAUDE.md README.md CHANGES.md LICENSE version.txt .gitignore \
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

# --------------------------------------------------------------- Probe fastapi
echo
echo "== Probe: Stack fastapi (mit Umgebung und Prüfungen)"

pdir="$tmp/probe-fastapi"
lauf 0 "Projekt entsteht, Prüfungen grün" \
    --name probe-fastapi --stack fastapi --owner musterorg \
    --purpose "Wegwerfprobe des Bootstraps." --dir "$pdir" --no-github

for datei in CLAUDE.md README.md Dockerfile compose.yaml compose.build.yaml \
             .env.example pyproject.toml requirements.txt requirements-dev.txt \
             app/main.py app/settings.py app/schemas.py \
             app/modules/beispiel/router.py app/modules/beispiel/service.py \
             app/modules/beispiel/schemas.py \
             tests/conftest.py tests/test_health.py tests/test_settings.py \
             deploy/install.sh deploy/update.sh deploy/backup.sh deploy/dev.sh compose.dev.yaml \
             deploy/smoke.sh deploy/smoke.txt scripts/komplexitaet-pruefen.sh scripts/konfig-pruefen.sh scripts/lizenzen-pruefen.sh \
             .vscode/settings.json .vscode/extensions.json .vscode/tasks.json \
             scripts/release-notes.sh scripts/check.sh \
             .github/workflows/tests.yml .github/workflows/release.yml .github/workflows/nightly.yml; do
    [ -f "$pdir/$datei" ] && ok "vorhanden: $datei" || nichtok "fehlt: $datei"
done

(cd "$pdir" && bash deploy/smoke.sh --dry-run) | grep -q '^/healthz .*Status 200' \
    && ok "deploy/smoke.sh --dry-run listet die Routen" || nichtok "deploy/smoke.sh --dry-run listet die Routen"
[ "$(git -C "$pdir" ls-files -s deploy/smoke.sh | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: deploy/smoke.sh" || nichtok "Ausführbar-Bit im Index: deploy/smoke.sh"
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

pdir="$tmp/probe-astro"
lauf 0 "Projekt entsteht, Prüfungen grün" \
    --name probe-astro --stack astro --owner musterorg \
    --purpose "Wegwerfprobe des Bootstraps." --dir "$pdir" --no-github

for datei in CLAUDE.md README.md Dockerfile compose.yaml compose.build.yaml \
             .env.example package.json package-lock.json astro.config.mjs \
             tsconfig.json \
             src/layouts/Base.astro src/pages/index.astro src/pages/404.astro \
             src/styles/global.css public/robots.txt public/favicon.svg \
             tests/build.test.mjs .claude/rules/inhalt.md .claude/rules/tests.md docker/Caddyfile \
             tests/e2e/playwright.config.ts tests/e2e/smoke.spec.ts tests/e2e/sweep.spec.ts tests/e2e/tsconfig.json \
             deploy/install.sh deploy/update.sh deploy/backup.sh deploy/dev.sh compose.dev.yaml \
             deploy/smoke.sh deploy/smoke.txt scripts/komplexitaet-pruefen.sh scripts/konfig-pruefen.sh scripts/lizenzen-pruefen.sh \
             .vscode/settings.json .vscode/extensions.json .vscode/tasks.json \
             scripts/release-notes.sh \
             .github/workflows/tests.yml .github/workflows/release.yml \
             .github/dependabot.yml \
             dist/index.html dist/404.html dist/sitemap-index.xml; do
    [ -f "$pdir/$datei" ] && ok "vorhanden: $datei" || nichtok "fehlt: $datei"
done

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
             config/application.php config/environments/development.php \
             web/index.php web/wp-config.php web/wp/wp-settings.php \
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
             deploy/smoke.sh deploy/smoke.txt scripts/komplexitaet-pruefen.sh scripts/konfig-pruefen.sh scripts/lizenzen-pruefen.sh \
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

echo
if [ "$fehler" -eq 0 ]; then
    echo "Alle Fälle grün."
else
    echo "Fehler: $fehler"
    exit 1
fi
