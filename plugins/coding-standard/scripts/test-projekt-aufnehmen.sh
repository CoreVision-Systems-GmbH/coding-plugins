#!/usr/bin/env bash
# Prüft projekt-aufnehmen.sh: Argumente, Bestandsaufnahme, --apply, Idempotenz, Vault.
#
#     bash plugins/coding-standard/scripts/test-projekt-aufnehmen.sh
#
# Legt in einem Wegwerf-Verzeichnis zwei Bestandsrepos an — ein Laravel-ähnliches mit
# composer.json, package.json und Tag, und ein Werkzeug ohne Markerdatei —, nimmt sie auf
# und prüft das Ergebnis. Kein Netz, kein GitHub, nichts außerhalb von $TMPDIR.

set -u

hier="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$hier/.." && pwd)"
skript="$hier/projekt-aufnehmen.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export GIT_AUTHOR_NAME=Probe GIT_AUTHOR_EMAIL=probe@example.invalid
export GIT_COMMITTER_NAME=Probe GIT_COMMITTER_EMAIL=probe@example.invalid

fehler=0
ok()      { echo "ok     $1"; }
nichtok() { echo "FEHLER $1"; fehler=$((fehler + 1)); }

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

enthaelt() { # <name> <text, fest>
    if grep -qF -- "$2" <<<"$LETZTE_AUSGABE"; then ok "$1"; else nichtok "$1 (nicht in der Ausgabe: $2)"; fi
}
enthaelt_muster() { # <name> <ERE>
    if grep -qE -- "$2" <<<"$LETZTE_AUSGABE"; then ok "$1"; else nichtok "$1 (Muster fehlt: $2)"; fi
}

hook_stacks() { # <projektdir> → Zeile "Stack erkannt: ..."
    (cd "$1" && env CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$1" \
        bash "$root/hooks/standard-context.sh") | head -1
}

git_repo() { # <dir> [remote-url]
    git -C "$1" init -q -b main
    git -C "$1" add -A
    git -C "$1" commit -q -m "Bestand"
    [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"
}

# ------------------------------------------------------- Bestand: Laravel
a="$tmp/bestand-laravel"
mkdir -p "$a/config" "$a/bootstrap" "$a/.github/workflows"
cat > "$a/composer.json" <<'EOF'
{
    "name": "musterorg/bestand-laravel",
    "require": {
        "php": "^8.4",
        "laravel/framework": "^13.0"
    },
    "scripts": {
        "post-autoload-dump": [
            "@php artisan package:discover --ansi"
        ],
        "setup": [
            "composer install",
            "@php artisan migrate --force"
        ],
        "ci:setup": [
            "composer install"
        ],
        "lint": "pint",
        "test": [
            "@php artisan test"
        ]
    }
}
EOF
cat > "$a/package.json" <<'EOF'
{
  "private": true,
  "scripts": {
    "build": "vite build",
    "dev": "vite"
  },
  "devDependencies": {
    "vite": "^8.0.0"
  }
}
EOF
printf '# Bestand Laravel\n\nVerwaltet die Leads des Musterkunden für den Außendienst.\n\n## Einrichtung\n\n- Punkt\n' > "$a/README.md"
printf '<?php\nreturn [\n    "name" => "Bestand",\n];\n' > "$a/config/app.php"
printf '<?php\n// Bestand ohne Proxy-Einstellung.\n' > "$a/bootstrap/app.php"
printf 'name: tests\non: [push]\njobs:\n  ci:\n    runs-on: ubuntu-latest\n' > "$a/.github/workflows/tests.yml"
printf '# Änderungen\n\n## [1.2.0] — 2026-01-01\n\n- Alt.\n' > "$a/CHANGES.md"
git_repo "$a" "https://github.com/musterorg/bestand-laravel.git"
git -C "$a" tag v1.2.0

echo "== Argumente"
lauf 0 "--help endet sauber" --help
lauf 1 "unbekannte Option wird abgewiesen" --gibtesnicht
mkdir -p "$tmp/kein-repo"
lauf 1 "kein Git-Repo wird abgewiesen" --dir "$tmp/kein-repo"
lauf 1 "unbekannter Stack wird abgewiesen" --dir "$a" --stack rubyonrails
enthaelt "Meldung nennt den unbekannten Stack" "Unbekannter Stack"
lauf 1 "Unterordner statt Wurzel wird abgewiesen" --dir "$a/config"

echo
echo "== Bestandsaufnahme (liest nur)"
lauf 0 "Bericht endet mit 0" --dir "$a"
enthaelt "Stack laravel erkannt" "Stack:    laravel"
enthaelt "Remote erkannt" "Remote:   https://github.com/musterorg/bestand-laravel.git"
enthaelt "nicht erklärt" "Erklärt:  nein"
enthaelt_muster "Stufe 1: CLAUDE.md fehlt" 'fehlt +CLAUDE\.md'
enthaelt_muster "Stufe 1: README.md vorhanden" 'ok +README\.md'
enthaelt_muster "Stufe 1: CHANGES.md ohne „Unveröffentlicht“" 'fehlt +CHANGES\.md hat einen Abschnitt'
enthaelt_muster "Stufe 2: Dockerfile fehlt, Vorlage genannt" 'fehlt +Dockerfile +← templates/laravel/dateien/Dockerfile'
enthaelt_muster "Stufe 2: Rauchtest fehlt, Vorlage genannt" 'fehlt +deploy/smoke\.txt +← templates/laravel/dateien/deploy/smoke\.txt'
enthaelt_muster "Stufe 2: Konfigurationsprüfung fehlt, Vorlage genannt" 'fehlt +scripts/konfig-pruefen\.sh +← templates/laravel/dateien/scripts/konfig-pruefen\.sh'
enthaelt_muster "Stufe 2: tests.yml heißt ci" 'ok +tests\.yml: Auftrag heißt'
enthaelt_muster "Stufe 2: Diff-Abdeckung fehlt" 'fehlt +tests\.yml: Schritt „Diff-Abdeckung“'
enthaelt_muster "Stufe 2: nightly.yml fehlt, Vorlage genannt" 'fehlt +nightly\.yml: .*← templates/laravel/dateien/\.github/workflows/nightly\.yml'

enthaelt_muster "Stufe 2: PR-Text-Schritt fehlt" 'fehlt +tests\.yml: Schritt „PR-Text prüfen“'
enthaelt_muster "Stufe 3: Fassung im Produkt fehlt" 'fehlt +Fassung im Produkt'
enthaelt_muster "Stufe 3: TrustProxies fehlt" 'fehlt +TrustProxies'
enthaelt_muster "Stufe 3: Härtung fehlt" 'fehlt +compose\.yaml: Härtung'
enthaelt_muster "Stufe 3: Script lint vorhanden" 'ok +composer\.json: Script „lint“'
enthaelt_muster "Stufe 3: Script types:check fehlt" 'fehlt +composer\.json: Script „types:check“'
enthaelt_muster "Stufe 3: pint.json fehlt, Vorlage genannt" 'fehlt +pint\.json: .*← templates/laravel/dateien/pint\.json'
enthaelt_muster "Stufe 3: Kennzahlen fehlen, Vorlage genannt" 'fehlt +Kennzahlen je Funktion .*← templates/laravel/dateien/phpmd\.xml'
enthaelt_muster "Stufe 1: Editor-Dateien fehlen, Vorlage genannt" 'fehlt +\.vscode/tasks\.json .*← templates/laravel/dateien/\.vscode/tasks\.json'
# Fall „vorhanden“: mit beiden Dateien aus der Vorlage meldet die Stufe ok — und ändert nichts.
cp "$root/templates/laravel/dateien/phpmd.xml" "$root/templates/laravel/dateien/scripts/komplexitaet-pruefen.sh" "$a/" 2>/dev/null || true
mkdir -p "$a/scripts" && mv "$a/komplexitaet-pruefen.sh" "$a/scripts/"
lauf 0 "Bericht mit Kennzahlen-Dateien endet mit 0" --dir "$a"
enthaelt_muster "Stufe 3: Kennzahlen vorhanden" 'ok +Kennzahlen je Funktion'
rm -f "$a/phpmd.xml" "$a/scripts/komplexitaet-pruefen.sh"
enthaelt_muster "Stufe 3: Script check fehlt" 'fehlt +composer\.json: Script „check“'
enthaelt "Zusammenfassung mit Zählern" "Stufe 3 Betriebsvertrag:"
[ -z "$(git -C "$a" status --porcelain)" ] && ok "Bericht hat nichts geändert" || nichtok "Bericht hat nichts geändert"

echo
echo "== --apply"
touch "$a/schmutzig.txt"
lauf 1 "--apply verweigert bei unsauberem Arbeitsbaum" --dir "$a" --apply
enthaelt "Meldung nennt den Arbeitsbaum" "nicht sauber"
rm "$a/schmutzig.txt"

lauf 0 "--apply legt Stufe 0 und 1 an" --dir "$a" --apply --customer "Musterkunde auf host1"
for datei in .claude/settings.json CLAUDE.md LICENSE version.txt .editorconfig .gitattributes \
             .githooks/pre-commit .gitleaks.toml \
             .github/CODEOWNERS .github/pull_request_template.md scripts/pr-text-pruefen.sh \
             .github/workflows/claude-review.yml .github/dependabot.yml \
             docs/status.md docs/decisions/0000-vorlage.md \
             docs/decisions/0001-aufnahme-firmenstandard.md \
             .claude/rules/tests.md .claude/rules/filament.md .claude/rules/frontend.md; do
    [ -f "$a/$datei" ] && ok "angelegt: $datei" || nichtok "fehlt: $datei"
done
[ -f "$a/docs/decisions/0001-projektstart.md" ] \
    && nichtok "kein Projektstart-ADR für Bestand" || ok "kein Projektstart-ADR für Bestand"
[ -f "$a/Dockerfile" ] \
    && nichtok "--apply legt keinen Lieferweg an" || ok "--apply legt keinen Lieferweg an"
[ -f "$a/.coding-standard" ] \
    && nichtok "laravel braucht keine Markerdatei" || ok "laravel braucht keine Markerdatei"
git -C "$a" diff --quiet \
    && ok "keine bestehende Datei geändert" || nichtok "keine bestehende Datei geändert"
bash "$a/scripts/pr-text-pruefen.sh" "$a/.github/pull_request_template.md" >/dev/null 2>&1 \
    && nichtok "PR-Text-Prüfer erkennt die leere Vorlage" || ok "PR-Text-Prüfer erkennt die leere Vorlage"
grep -q '^1.2.0$' "$a/version.txt" \
    && ok "version.txt aus dem Tag v1.2.0" || nichtok "version.txt aus dem Tag v1.2.0"
grep -q 'composer ci:setup' "$a/CLAUDE.md" \
    && ok "CLAUDE.md nennt composer ci:setup" || nichtok "CLAUDE.md nennt composer ci:setup"
grep -q 'npm run build' "$a/CLAUDE.md" \
    && ok "CLAUDE.md nennt npm run build" || nichtok "CLAUDE.md nennt npm run build"
grep -q 'post-autoload-dump' "$a/CLAUDE.md" \
    && nichtok "Composer-Hooks bleiben draußen" || ok "Composer-Hooks bleiben draußen"
grep -q 'Verwaltet die Leads des Musterkunden' "$a/CLAUDE.md" \
    && ok "Zweck aus der README" || nichtok "Zweck aus der README"
grep -q 'Musterkunde auf host1' "$a/CLAUDE.md" \
    && ok "Kunde eingesetzt" || nichtok "Kunde eingesetzt"
grep -qE '^\* @[A-Za-z0-9-]+' "$a/.github/CODEOWNERS" \
    && ok "CODEOWNERS trägt ein Konto" || nichtok "CODEOWNERS trägt ein Konto"
[ -f "$a/.vscode/tasks.json" ] && [ -f "$a/.vscode/settings.json" ] && [ -f "$a/.vscode/extensions.json" ] \
    && grep -q 'composer check' "$a/.vscode/tasks.json" \
    && ok ".vscode/ des Stacks angelegt (Aufgabe ruft composer check)" || nichtok ".vscode/ des Stacks angelegt (Aufgabe ruft composer check)"
grep -q 'Stufe 2: Dockerfile' "$a/docs/decisions/0001-aufnahme-firmenstandard.md" \
    && ok "ADR nennt die Lücke Dockerfile" || nichtok "ADR nennt die Lücke Dockerfile"
grep -q 'Stufe 3: Fassung im Produkt' "$a/docs/decisions/0001-aufnahme-firmenstandard.md" \
    && ok "ADR nennt die Lücke Fassung im Produkt" || nichtok "ADR nennt die Lücke Fassung im Produkt"
grep -q 'Stufe 1:' "$a/docs/decisions/0001-aufnahme-firmenstandard.md" \
    && nichtok "ADR listet keine Stufe-1-Lücken (die legt --apply an)" \
    || ok "ADR listet keine Stufe-1-Lücken (die legt --apply an)"
grep -q 'Stufe 2: Dockerfile' "$a/docs/status.md" \
    && ok "status.md nennt die Lücken" || nichtok "status.md nennt die Lücken"
grep -q 'Laravel 13' "$a/docs/decisions/0001-aufnahme-firmenstandard.md" \
    && ok "ADR nennt den Stack" || nichtok "ADR nennt den Stack"
grep -rlE '\{\{[A-Z_][A-Z0-9_]*\}\}' "$a" --exclude-dir=.git >/dev/null 2>&1 \
    && nichtok "keine unersetzten Platzhalter" || ok "keine unersetzten Platzhalter"
hook_stacks "$a" | grep -q 'Stack erkannt: laravel' \
    && ok "Hook aktiv nach der Aufnahme" || nichtok "Hook aktiv nach der Aufnahme"

echo
echo "== Idempotenz"
git -C "$a" add -A && git -C "$a" commit -q -m "chore: Aufnahme in den Firmenstandard"
lauf 0 "zweiter --apply-Lauf endet sauber" --dir "$a" --apply
enthaelt "zweiter Lauf legt nichts an" "0 Datei(en) angelegt"
[ -z "$(git -C "$a" status --porcelain)" ] \
    && ok "zweiter Lauf ändert nichts" || nichtok "zweiter Lauf ändert nichts"
lauf 0 "Bericht nach der Aufnahme" --dir "$a"
enthaelt "jetzt erklärt" "Erklärt:  ja — .claude/settings.json"
sed -n '/"deny"/,/\]/p' "$a/.claude/settings.json" | grep -q '"Read(.env)"' \
    && ok "settings.json sperrt .env für Sessions (im deny-Block)" || nichtok "settings.json sperrt .env für Sessions (im deny-Block)"
enthaelt_muster "CLAUDE.md jetzt vorhanden" 'ok +CLAUDE\.md'
enthaelt_muster "CLAUDE.md hat Befehle" 'ok +CLAUDE\.md hat einen Abschnitt „Befehle“'
enthaelt_muster "version.txt entspricht dem Tag" 'ok +version\.txt entspricht dem letzten Tag'

# ------------------------------------------------------ Bestand: Werkzeug
echo
echo "== Werkzeug ohne Markerdatei (script)"
b="$tmp/bestand-werkzeug"
mkdir -p "$b/scripts"
printf '#!/usr/bin/env bash\necho hallo\n' > "$b/scripts/hallo.sh"
printf '# Werkzeug\n\nRäumt alte Sicherungen auf den Hosts auf.\n' > "$b/README.md"
git_repo "$b"

lauf 0 "ohne Stack: Bericht endet mit 0" --dir "$b"
enthaelt "kein Stack erkannt" "keiner erkannt"
lauf 0 "mit --stack script: Bericht endet mit 0" --dir "$b" --stack script
enthaelt_muster "Stufe 3 (script): Kennzahlen fehlen, Vorlage genannt" 'fehlt +Kennzahlen je Funktion .*← templates/script/dateien/scripts/komplexitaet-pruefen\.sh'
lauf 1 "--apply ohne origin und ohne --owner wird abgewiesen" --dir "$b" --apply --stack script
enthaelt "Meldung nennt --owner" "--owner"
lauf 0 "--apply mit --stack script und --owner" --dir "$b" --apply --stack script --owner musterorg
grep -q 'Datenbank: keine\.' "$b/CLAUDE.md" \
    && ok "CLAUDE.md nennt die Zieldatenbank des Stacks (keine)" \
    || nichtok "CLAUDE.md nennt die Zieldatenbank des Stacks (keine)"
grep -q 'stack: script' "$b/.coding-standard" \
    && ok "Markerdatei nennt script" || nichtok "Markerdatei nennt script"
grep -q '^0.1.0$' "$b/version.txt" \
    && ok "version.txt ohne Tag: 0.1.0" || nichtok "version.txt ohne Tag: 0.1.0"
grep -q 'Befehle des Projekts eintragen' "$b/CLAUDE.md" \
    && ok "CLAUDE.md: Hinweis statt erfundener Befehle" || nichtok "CLAUDE.md: Hinweis statt erfundener Befehle"
[ -f "$b/.claude/rules/tests.md" ] \
    && ok "Regeln des Stacks script" || nichtok "Regeln des Stacks script"
[ -f "$b/.githooks/pre-commit" ] && [ -f "$b/.gitleaks.toml" ] \
    && ok "pre-commit-Hook und .gitleaks.toml angelegt" || nichtok "pre-commit-Hook und .gitleaks.toml angelegt"
# Das Bit kommt nur über den Index ins Repo (Windows: core.fileMode=false); der Hook ist
# deshalb schon vorgemerkt, alles andere bleibt unversioniert bis zum Commit des Menschen.
[ "$(git -C "$b" ls-files -s .githooks/pre-commit | cut -c1-6)" = "100755" ] \
    && ok "Ausführbar-Bit im Index: .githooks/pre-commit" \
    || nichtok "Ausführbar-Bit im Index: .githooks/pre-commit"
[ "$(git -C "$b" config core.hooksPath)" = ".githooks" ] \
    && ok "core.hooksPath zeigt auf .githooks" || nichtok "core.hooksPath zeigt auf .githooks"
grep -q 'Stufe 3: tests/' "$b/docs/status.md" \
    && ok "status.md nennt fehlende Tests" || nichtok "status.md nennt fehlende Tests"
hook_stacks "$b" | grep -q 'Stack erkannt: script' \
    && ok "Hook erkennt script" || nichtok "Hook erkennt script"

echo
echo "== Vault"
v="$tmp/vault"
mkdir -p "$v/05-daily"
git -C "$b" add -A && git -C "$b" commit -q -m "chore: Aufnahme"
lauf 0 "--apply mit --vault" --dir "$b" --apply --stack script --owner musterorg --vault "$v"
[ -f "$v/04-projects/bestand-werkzeug/README.md" ] \
    && ok "Vault-Akte angelegt" || nichtok "Vault-Akte angelegt"
grep -q 'aufgenommen: \[\[bestand-werkzeug\]\]' "$v/05-daily/$(date +%Y-%m-%d).md" 2>/dev/null \
    && ok "Daily-Log-Zeile" || nichtok "Daily-Log-Zeile"

# ------------------------------------------- Bestand: erklärt, aber alte settings.json
echo
echo "== Bestand mit älterer settings.json (ohne permissions)"
c="$tmp/bestand-alt"
mkdir -p "$c/.claude" "$c/scripts"
printf '{\n  "enabledPlugins": { "coding-standard@corevision": true }\n}\n' > "$c/.claude/settings.json"
printf '#!/usr/bin/env bash\necho hallo\n' > "$c/scripts/hallo.sh"
printf '# Alt\n\nWerkzeug mit älterer Erklärung.\n' > "$c/README.md"
git_repo "$c"
lauf 0 "Bericht endet mit 0" --dir "$c"
enthaelt "bereits erklärt" "Erklärt:  ja"
enthaelt_muster "Stufe 1: fehlende permissions werden gemeldet" 'fehlt +\.claude/settings\.json: permissions'
lauf 0 "--apply mit --stack script und --owner" --dir "$c" --apply --stack script --owner musterorg
grep -q '"permissions"' "$c/.claude/settings.json" \
    && nichtok "ältere settings.json wird nicht überschrieben" || ok "ältere settings.json wird nicht überschrieben"
grep -q 'settings.json ohne `permissions`' "$c/docs/status.md" \
    && ok "status.md nennt die fehlende Sperrliste als Lücke" || nichtok "status.md nennt die fehlende Sperrliste als Lücke"
grep -q 'settings.json ohne `permissions`' "$c"/docs/decisions/0001-aufnahme-firmenstandard.md \
    && ok "ADR nennt die fehlende Sperrliste als Lücke" || nichtok "ADR nennt die fehlende Sperrliste als Lücke"

echo
echo "== Bestand mit eigenem Hook-Ordner (core.hooksPath bleibt)"
d="$tmp/bestand-husky"
mkdir -p "$d/scripts" "$d/.husky/_"
printf '#!/usr/bin/env bash\necho hallo\n' > "$d/scripts/hallo.sh"
printf '#!/usr/bin/env sh\nexit 0\n' > "$d/.husky/_/pre-commit"
printf '# Husky\n\nWerkzeug mit eigenen Hooks.\n' > "$d/README.md"
git_repo "$d"
git -C "$d" config core.hooksPath .husky/_
lauf 0 "--apply bei bestehendem core.hooksPath" --dir "$d" --apply --stack script --owner musterorg
enthaelt "Meldung nennt den bestehenden Hook-Ordner" "core.hooksPath bleibt auf '.husky/_'"
[ "$(git -C "$d" config core.hooksPath)" = ".husky/_" ] \
    && ok "bestehender core.hooksPath wird nicht überschrieben" || nichtok "bestehender core.hooksPath wird nicht überschrieben"
[ -f "$d/.githooks/pre-commit" ] \
    && ok "Hook-Datei trotzdem angelegt (zum Einhängen)" || nichtok "Hook-Datei trotzdem angelegt (zum Einhängen)"

# ------------------------------------------------------ Bestand: Datenbank
echo
echo "== Datenbank des Bestands (PostgreSQL, Ausnahme MariaDB für WordPress)"
grep -q 'Datenbank: PostgreSQL 18\.' "$a/CLAUDE.md" \
    && ok "ohne erkennbare Datenbank: CLAUDE.md nennt die der Vorlage (PostgreSQL 18)" \
    || nichtok "ohne erkennbare Datenbank: CLAUDE.md nennt die der Vorlage (PostgreSQL 18)"

e="$tmp/bestand-mysql"
mkdir -p "$e"
printf '# MySQL\n\nFachanwendung auf MySQL.\n' > "$e/README.md"
printf 'APP_NAME=Bestand\nDB_CONNECTION=mysql\nDB_HOST=db\n' > "$e/.env.example"
git_repo "$e"
lauf 0 "MySQL: Bericht endet mit 0" --dir "$e" --stack laravel
enthaelt_muster "MySQL statt PostgreSQL wird gemeldet" 'fehlt +Datenbank: MySQL statt PostgreSQL'
lauf 0 "MySQL: --apply" --dir "$e" --apply --stack laravel --owner musterorg
grep -q 'Datenbank: MySQL — Abweichung vom Standard (PostgreSQL), ADR fehlt\.' "$e/CLAUDE.md" \
    && ok "CLAUDE.md nennt MySQL samt Abweichung, nicht die Vorlage" \
    || nichtok "CLAUDE.md nennt MySQL samt Abweichung, nicht die Vorlage"
grep -q 'Stufe 3: Datenbank: MySQL statt PostgreSQL' "$e/docs/decisions/0001-aufnahme-firmenstandard.md" \
    && ok "ADR der Aufnahme listet die Abweichung als Lücke" \
    || nichtok "ADR der Aufnahme listet die Abweichung als Lücke"
git -C "$e" add -A && git -C "$e" commit -q -m "chore: Aufnahme"
lauf 0 "MySQL: Bericht nach der Aufnahme" --dir "$e" --stack laravel
enthaelt_muster "ADR der Aufnahme zählt nicht als Begründung" 'fehlt +Datenbank: MySQL statt PostgreSQL'
printf '# 0002 — Zwischenspeicher\n\nRedis statt einer MySQL-Tabelle.\n' > "$e/docs/decisions/0002-cache.md"
lauf 0 "MySQL mit beiläufiger Erwähnung: Bericht endet mit 0" --dir "$e" --stack laravel
enthaelt_muster "beiläufige Erwähnung im ADR-Text zählt nicht" 'fehlt +Datenbank: MySQL statt PostgreSQL'
printf '# 0003 — MySQL bleibt\n\nDer Kunde betreibt die Datenbank selbst.\n' > "$e/docs/decisions/0003-datenbank-mysql.md"
lauf 0 "MySQL mit ADR: Bericht endet mit 0" --dir "$e" --stack laravel
enthaelt_muster "ADR mit der Datenbank im Titel begründet die Abweichung" 'ok +Datenbank: MySQL statt PostgreSQL — Abweichung begründet in docs/decisions/0003-datenbank-mysql\.md'

f="$tmp/bestand-compose"
mkdir -p "$f"
printf '# Compose\n\nDienst mit Verbund.\n' > "$f/README.md"
printf 'DB_CONNECTION=sqlite\n' > "$f/.env.example"
printf 'services:\n    app:\n        image: ghcr.io/musterorg/mysql-abgleich:${APP_VERSION}\n    db:\n        image: "postgres:18-alpine"\n' > "$f/compose.yaml"
git_repo "$f"
lauf 0 "Compose: --apply" --dir "$f" --apply --stack laravel --owner musterorg
enthaelt_muster "Compose-Abbild geht vor .env.example, Anwendungsname zählt nicht" 'ok +Datenbank: PostgreSQL \(Standard\)'
grep -q 'Datenbank: PostgreSQL 18\.' "$f/CLAUDE.md" \
    && ok "gleiche Datenbank wie die Vorlage: CLAUDE.md behält deren Fassung (PostgreSQL 18)" \
    || nichtok "gleiche Datenbank wie die Vorlage: CLAUDE.md behält deren Fassung (PostgreSQL 18)"

m="$tmp/bestand-abbilder"
mkdir -p "$m"
printf '# Abbilder\n\nDienst mit Abbild aus einer Variablen.\n' > "$m/README.md"
printf 'DB_CONNECTION=pgsql\n' > "$m/.env.example"
printf 'services:\n    db:\n        image: ${DB_IMAGE:-mysql:8.4}\n' > "$m/compose.yaml"
git_repo "$m"
lauf 0 "Abbild aus Variable: Bericht endet mit 0" --dir "$m" --stack laravel
enthaelt_muster "Vorgabe hinter \${VAR:-…} zählt als Abbild" 'fehlt +Datenbank: MySQL statt PostgreSQL'
printf 'services:\n    db:\n        image: mongo:8\n' > "$m/compose.yaml"
lauf 0 "MongoDB: Bericht endet mit 0" --dir "$m" --stack laravel
enthaelt_muster "MongoDB wird gemeldet" 'fehlt +Datenbank: MongoDB statt PostgreSQL'

g="$tmp/bestand-wordpress"
mkdir -p "$g"
printf '# Site\n\nWebsite.\n' > "$g/README.md"
printf 'services:\n    db:\n        image: mariadb:11.8\n' > "$g/compose.yaml"
git_repo "$g"
lauf 0 "WordPress mit MariaDB: Bericht endet mit 0" --dir "$g" --stack wordpress
enthaelt_muster "WordPress mit MariaDB ist Standard" 'ok +Datenbank: MariaDB \(Standard\)'
printf 'services:\n    db:\n        image: docker.io/library/mysql:8.4\n' > "$g/compose.yaml"
lauf 0 "WordPress mit MySQL: Bericht endet mit 0" --dir "$g" --stack wordpress
enthaelt_muster "WordPress mit MySQL wird gemeldet" 'fehlt +Datenbank: MySQL statt MariaDB'

h="$tmp/bestand-sqlite-werkzeug"
mkdir -p "$h/scripts"
printf '#!/usr/bin/env bash\necho hallo\n' > "$h/scripts/hallo.sh"
printf '# Auswertung\n\nWertet Messdaten aus.\n' > "$h/README.md"
printf 'AUSWERTUNG_DATABASE_URL=sqlite:///data/messwerte.db\n' > "$h/.env.example"
git_repo "$h"
lauf 0 "Skript mit SQLite: --apply" --dir "$h" --apply --stack script --owner musterorg
enthaelt_muster "SQLite im Skript ohne Dienst ist Standard" 'ok +Datenbank: SQLite \(Standard\)'
grep -q 'Datenbank: SQLite\.' "$h/CLAUDE.md" \
    && ok "CLAUDE.md nennt SQLite statt „keine“" || nichtok "CLAUDE.md nennt SQLite statt „keine“"

k="$tmp/bestand-ohne-stack"
mkdir -p "$k"
printf '# Dienst\n\nEin Dienst ohne Vorlage.\n' > "$k/README.md"
printf 'DIENST_DATABASE_URL=postgresql+psycopg://dienst@db/dienst\n' > "$k/.env.example"
git_repo "$k"
lauf 0 "ohne Stack mit DATABASE_URL: Bericht endet mit 0" --dir "$k"
enthaelt_muster "DATABASE_URL mit Treiberzusatz erkannt" 'ok +Datenbank: PostgreSQL \(Standard\)'
printf 'TEST_DATABASE_URL=sqlite:///:memory:\nDIENST_DATABASE_URL=postgresql://dienst@db/dienst\n' > "$k/.env.example"
lauf 0 "Testdatenbank vor der Betriebsdatenbank: Bericht endet mit 0" --dir "$k"
enthaelt_muster "TEST_DATABASE_URL zählt nicht als Betriebsdatenbank" 'ok +Datenbank: PostgreSQL \(Standard\)'
printf 'DIENST_DATABASE_URL=sqlite:///dienst.db\n' > "$k/.env.example"
lauf 0 "ohne Stack mit SQLite: Bericht endet mit 0" --dir "$k"
enthaelt_muster "SQLite außerhalb eines Skripts wird gemeldet" 'fehlt +Datenbank: SQLite statt PostgreSQL'

n="$tmp/bestand-fastapi-sqlite"
mkdir -p "$n"
printf '# Dienst\n\nFastAPI-Dienst auf SQLite.\n' > "$n/README.md"
printf 'DIENST_DATABASE_URL=sqlite:///data/dienst.db\n' > "$n/.env.example"
git_repo "$n"
lauf 0 "FastAPI mit SQLite: --apply" --dir "$n" --apply --stack fastapi --owner musterorg
grep -q 'Datenbank: SQLite — Abweichung vom Standard (PostgreSQL), ADR fehlt\.' "$n/CLAUDE.md" \
    && ok "Abweichung steht in der CLAUDE.md, auch wenn die Vorlage denselben Namen trägt" \
    || nichtok "Abweichung steht in der CLAUDE.md, auch wenn die Vorlage denselben Namen trägt"

echo
if [ "$fehler" -eq 0 ]; then
    echo "Alle Fälle grün."
else
    echo "Fehler: $fehler"
    exit 1
fi
