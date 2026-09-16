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
enthaelt_muster "Stufe 2: tests.yml heißt ci" 'ok +tests\.yml: Auftrag heißt'
enthaelt_muster "Stufe 3: Fassung im Produkt fehlt" 'fehlt +Fassung im Produkt'
enthaelt_muster "Stufe 3: TrustProxies fehlt" 'fehlt +TrustProxies'
enthaelt_muster "Stufe 3: Script lint vorhanden" 'ok +composer\.json: Script „lint“'
enthaelt_muster "Stufe 3: Script types:check fehlt" 'fehlt +composer\.json: Script „types:check“'
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
             .github/CODEOWNERS .github/pull_request_template.md \
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
lauf 1 "--apply ohne origin und ohne --owner wird abgewiesen" --dir "$b" --apply --stack script
enthaelt "Meldung nennt --owner" "--owner"
lauf 0 "--apply mit --stack script und --owner" --dir "$b" --apply --stack script --owner musterorg
grep -q 'stack: script' "$b/.coding-standard" \
    && ok "Markerdatei nennt script" || nichtok "Markerdatei nennt script"
grep -q '^0.1.0$' "$b/version.txt" \
    && ok "version.txt ohne Tag: 0.1.0" || nichtok "version.txt ohne Tag: 0.1.0"
grep -q 'Befehle des Projekts eintragen' "$b/CLAUDE.md" \
    && ok "CLAUDE.md: Hinweis statt erfundener Befehle" || nichtok "CLAUDE.md: Hinweis statt erfundener Befehle"
[ -f "$b/.claude/rules/tests.md" ] \
    && ok "Regeln des Stacks script" || nichtok "Regeln des Stacks script"
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

echo
if [ "$fehler" -eq 0 ]; then
    echo "Alle Fälle grün."
else
    echo "Fehler: $fehler"
    exit 1
fi
