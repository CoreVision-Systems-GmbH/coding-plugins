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
             .claude/settings.json .claude/rules/tests.md \
             .github/CODEOWNERS .github/dependabot.yml \
             .github/pull_request_template.md .github/workflows/tests.yml \
             .github/workflows/claude-review.yml \
             docs/status.md docs/decisions/0001-projektstart.md \
             scripts/beispiel.sh scripts/beispiel.py \
             tests/test_beispiel.py tests/test_beispiel_sh.sh; do
    [ -f "$pdir/$datei" ] && ok "vorhanden: $datei" || nichtok "fehlt: $datei"
done

[ -f "$pdir/Dockerfile" ] \
    && nichtok "script-Stack liefert kein Dockerfile" \
    || ok "script-Stack liefert kein Dockerfile"

grep -rlE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$pdir" >/dev/null 2>&1 \
    && nichtok "keine unersetzten Platzhalter" \
    || ok "keine unersetzten Platzhalter"

grep -q 'probe-script' "$pdir/CLAUDE.md" \
    && ok "CLAUDE.md trägt den Projektnamen" || nichtok "CLAUDE.md trägt den Projektnamen"
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

hook_stacks "$pdir" | grep -q 'Stack erkannt: script' \
    && ok "Hook erkennt den Stack script" || nichtok "Hook erkennt den Stack script"

bash "$pdir/tests/test_beispiel_sh.sh" >/dev/null 2>&1 \
    && ok "Beispiel-Shelltest läuft im neuen Projekt" \
    || nichtok "Beispiel-Shelltest läuft im neuen Projekt"

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
             tests/conftest.py tests/test_health.py \
             deploy/install.sh deploy/update.sh deploy/backup.sh \
             scripts/release-notes.sh \
             .github/workflows/tests.yml .github/workflows/release.yml; do
    [ -f "$pdir/$datei" ] && ok "vorhanden: $datei" || nichtok "fehlt: $datei"
done

grep -rlE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$pdir" --exclude-dir=.venv >/dev/null 2>&1 \
    && nichtok "keine unersetzten Platzhalter" \
    || ok "keine unersetzten Platzhalter"

grep -q 'env_prefix="FASTAPI_"' "$pdir/app/settings.py" \
    && ok "ENV-Präfix abgeleitet (FASTAPI_)" || nichtok "ENV-Präfix abgeleitet (FASTAPI_)"
grep -q 'ghcr.io/musterorg/probe-fastapi' "$pdir/compose.yaml" \
    && ok "compose.yaml zeigt auf das richtige Abbild" \
    || nichtok "compose.yaml zeigt auf das richtige Abbild"
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
             tests/build.test.mjs .claude/rules/inhalt.md docker/Caddyfile \
             deploy/install.sh deploy/update.sh deploy/backup.sh \
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

grep -q 'ghcr.io/musterorg/probe-astro' "$pdir/compose.yaml" \
    && ok "compose.yaml zeigt auf das richtige Abbild" \
    || nichtok "compose.yaml zeigt auf das richtige Abbild"
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
             compose.dev.yaml .env.example composer.json composer.lock wp-cli.yml \
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
             deploy/install.sh deploy/update.sh deploy/backup.sh \
             scripts/release-notes.sh \
             .github/workflows/tests.yml .github/workflows/release.yml \
             .github/dependabot.yml; do
    [ -f "$pdir/$datei" ] && ok "vorhanden: $datei" || nichtok "fehlt: $datei"
done

grep -rlE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$pdir" \
    --exclude-dir=vendor --exclude-dir=wp >/dev/null 2>&1 \
    && nichtok "keine unersetzten Platzhalter" \
    || ok "keine unersetzten Platzhalter"

grep -q 'ghcr.io/musterorg/probe-wordpress' "$pdir/compose.yaml" \
    && ok "compose.yaml zeigt auf das richtige Abbild" \
    || nichtok "compose.yaml zeigt auf das richtige Abbild"
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
