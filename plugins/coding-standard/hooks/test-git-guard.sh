#!/usr/bin/env bash
# test-git-guard.sh — Prüft git-guard.sh mit Beispiel-Nutzlasten.
#
# Aufruf:   bash plugins/coding-standard/hooks/test-git-guard.sh
# Ergebnis: Exit 0, wenn alle Fälle grün sind, sonst Exit 1.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/git-guard.sh"

[ -f "$GUARD" ] || { echo "git-guard.sh nicht gefunden: $GUARD"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Zwei Wegwerf-Repos: eines auf main, eines auf einem Feature-Zweig. Damit lässt sich
# "git push" ohne Ziel in beiden Lagen prüfen.
make_repo() {
  local path="$1" branch="$2"
  mkdir -p "$path"
  git -C "$path" init -q -b "$branch" >/dev/null 2>&1
  git -C "$path" config user.email "test@example.invalid" >/dev/null 2>&1
  git -C "$path" config user.name "Test" >/dev/null 2>&1
  : > "$path/datei.txt"
  git -C "$path" add datei.txt >/dev/null 2>&1
  git -C "$path" commit -q -m "init" >/dev/null 2>&1
}
make_repo "$TMP/auf-main" "main"
make_repo "$TMP/auf-feature" "feat/beispiel"
# Drittes Repo auf main mit Markerdatei: dort ist der Push auf main erlaubt (Vault-Fall).
make_repo "$TMP/auf-main-frei" "main"
: > "$TMP/auf-main-frei/.git-guard-main-ok"

# JSON-Nutzlast bauen. $1 = Befehl (bereits JSON-escaped), $2 = Arbeitsverzeichnis,
# $3 = Werkzeug (Bash oder PowerShell; der Hook hängt seit 1.1.0 an beiden).
payload() {
  printf '{"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s","description":"Testfall"}}' "$2" "${3:-Bash}" "$1"
}

TOTAL=0
FAILED=0

# check <block|allow> <arbeitsverzeichnis> <json-escaped befehl> <beschreibung> [werkzeug]
check() {
  local expected="$1" wd="$2" command_text="$3" label="$4" tool="${5:-Bash}"
  local output rc actual

  TOTAL=$((TOTAL + 1))
  output="$(cd "$wd" && payload "$command_text" "$wd" "$tool" | bash "$GUARD" 2>&1)"
  rc=$?

  actual="allow"
  case "$output" in
    *'"permissionDecision":"deny"'*) actual="block" ;;
  esac

  if [ "$rc" -ne 0 ]; then
    printf 'FEHLER  %-56s Exit %s statt 0\n' "$label" "$rc"
    FAILED=$((FAILED + 1))
    return
  fi

  if [ "$actual" != "$expected" ]; then
    printf 'FEHLER  %-56s erwartet %s, war %s\n' "$label" "$expected" "$actual"
    [ -n "$output" ] && printf '        Ausgabe: %s\n' "$output"
    FAILED=$((FAILED + 1))
    return
  fi

  if [ "$expected" = "allow" ] && [ -n "$output" ]; then
    printf 'FEHLER  %-56s erlaubt, aber Ausgabe: %s\n' "$label" "$output"
    FAILED=$((FAILED + 1))
    return
  fi

  printf 'ok      %-56s %s\n' "$label" "$expected"
}

M="$TMP/auf-main"
F="$TMP/auf-feature"
V="$TMP/auf-main-frei"

echo "== Blockiert =="
check block "$F" 'git push --force origin feat/beispiel'      '01 Force-Push mit --force'
check block "$F" 'git push -f origin feat/beispiel'           '02 Force-Push mit -f'
check block "$F" 'git push --force-with-lease origin main'    '03 --force-with-lease auf main'
check block "$F" 'git push origin main'                       '04 Push auf main'
check block "$F" 'git push -u origin master'                  '05 Push auf master mit -u'
check block "$F" 'git push origin HEAD:main'                  '06 Push HEAD:main'
check block "$M" 'git push'                                   '07 Push ohne Ziel, während auf main'
check block "$F" 'git push --delete origin alt'               '08 Remote-Zweig löschen (--delete)'
check block "$F" 'git push origin :alt'                       '09 Remote-Zweig löschen (:zweig)'
check block "$F" 'git push origin +feat/beispiel'             '10 Force über Refspec-Plus'
check block "$F" 'git reset --hard HEAD~1'                    '11 git reset --hard'
check block "$F" 'git clean -fdx'                             '12 git clean -fdx'
check block "$F" 'git clean -f'                               '13 git clean -f'
check block "$F" 'git branch -D feat/alt'                     '14 git branch -D'
check block "$F" 'git checkout -- .'                          '15 git checkout -- .'
check block "$F" 'git restore .'                              '16 git restore .'
check block "$F" 'git restore --staged .'                     '17 git restore --staged .'
check block "$F" 'rm -rf /'                                   '18 rm -rf /'
check block "$F" 'rm -rf ~'                                   '19 rm -rf ~'
check block "$F" 'rm -rf .'                                   '20 rm -rf .'
check block "$F" 'rm -rf *'                                   '21 rm -rf *'
check block "$F" 'rm -rf ..'                                  '22 rm -rf ..'
check block "$F" 'npm test && rm -rf /etc/hosts'              '23 rm -rf auf Fremdpfad in einer Kette'
check block "$F" 'git commit -m \"sagt \\\"hallo\\\"\" && git push --force' '24 Escapte Quotes plus Force-Push'
check block "$F" 'cd /tmp && git push origin main'            '25 Push auf main hinter einem cd'
check block "$F" 'git commit -m \"Gr\\u00fc\\u00dfe\" && git push -f' '26 Unicode-Escapes plus Force-Push'
check block "$F" 'sudo rm -rf /var/lib/docker'                '27 rm -rf mit sudo auf Fremdpfad'
check block "$V" 'git push --force origin main'               '44 Marker: Force-Push bleibt geblockt'
check block "$V" 'git reset --hard HEAD~1'                    '45 Marker: reset --hard bleibt geblockt'
check block "$V" 'git push --delete origin alt'               '46 Marker: Remote-Zweig löschen bleibt geblockt'

echo
echo "== Erlaubt =="
check allow "$F" 'git push origin v1.2.3'                     '28 Tag pushen'
check allow "$F" 'git push --tags'                            '29 Alle Tags pushen'
check allow "$F" 'git push -u origin feat/beispiel'           '30 Feature-Zweig pushen'
check allow "$F" 'git push'                                   '31 Push ohne Ziel auf Feature-Zweig'
check allow "$F" 'git push --force-with-lease origin feat/beispiel' '32 --force-with-lease auf eigenem Zweig'
check allow "$F" 'git status --porcelain'                     '33 git status'
check allow "$F" 'git clean -n'                               '34 git clean -n (Trockenlauf)'
check allow "$F" 'git branch -d feat/alt'                     '35 git branch -d (nur gemergt)'
check allow "$F" 'git checkout -- src/datei.php'              '36 Einzelne Datei zurücksetzen'
check allow "$F" 'git restore --staged src/datei.php'         '37 Einzelne Datei aus dem Index nehmen'
check allow "$F" 'git reset --soft HEAD~1'                    '38 git reset --soft'
check allow "$F" 'rm -rf node_modules'                        '39 rm -rf auf relativen Projektordner'
check allow "$F" 'rm -rf ./vendor/bin'                        '40 rm -rf auf relativen Unterpfad'
check allow "$F" 'echo \"kein git push --force hier\"'        '41 Schlagworte nur als Text in echo'
check allow "$F" 'npm ci && npm run build'                    '42 Gewöhnliche Build-Kette'
check allow "$F" 'git log --oneline -10 | head -3'            '43 Pipeline aus Lesebefehlen'
check allow "$V" 'git push'                                   '47 Marker .git-guard-main-ok: Push ohne Ziel auf main'
check allow "$V" 'git push origin main'                       '48 Marker: Push auf main mit Ziel'
check allow "$V" 'git add -A && git commit -m \"backup\" && git push' '49 Marker: Backup-Kette'

echo
echo "== Seit 1.0.0 blockiert: pauschales Stagen, --no-verify, Hook-Umbiegen, Datenbanklöscher =="
check block "$F" 'git add .'                                  '50 git add .'
check block "$F" 'git add -A'                                 '51 git add -A'
check block "$F" 'git add --all'                              '52 git add --all'
check block "$F" 'git add -u'                                 '53 git add -u'
check block "$F" 'git add -Av'                                '54 git add -Av (gebündelt)'
check block "$F" 'git add :/'                                 '55 git add :/ (ganzes Repo)'
check block "$F" 'git add . && git commit -m \"wip\"'         '56 git add . in einer Kette'
check block "$F" 'git commit --no-verify -m \"x\"'            '57 git commit --no-verify'
check block "$F" 'git commit -n -m \"x\"'                     '58 git commit -n'
check block "$F" 'git commit -am \"x\" --no-verify'           '59 --no-verify hinter -am'
check block "$F" 'git push --no-verify origin feat/beispiel'  '60 git push --no-verify'
check block "$F" 'git config core.hooksPath /tmp/leer'        '61 core.hooksPath umbiegen'
check block "$F" 'git config --unset core.hooksPath'          '62 core.hooksPath entfernen'
check block "$F" 'git config --global core.hooksPath /dev/null' '63 core.hooksPath global umbiegen'
check block "$F" 'git -c core.hooksPath=/tmp/leer commit -m \"x\"' '64 -c core.hooksPath für einen Aufruf'
check block "$F" 'php artisan migrate:fresh'                  '65 artisan migrate:fresh'
check block "$F" 'php artisan migrate:fresh --seed --force'   '66 artisan migrate:fresh mit Flags'
check block "$F" 'php artisan migrate:refresh'                '67 artisan migrate:refresh'
check block "$F" 'php artisan db:wipe --force'                '68 artisan db:wipe'
check block "$F" 'composer install && php artisan migrate:reset' '69 migrate:reset in einer Kette'
check block "$F" 'alembic downgrade base'                     '70 alembic downgrade base'
check block "$F" 'wp db reset --yes'                          '71 wp db reset'
check block "$V" 'git commit --no-verify -m \"backup\"'       '72 Marker: --no-verify bleibt geblockt'
check block "$V" 'php artisan db:wipe'                        '73 Marker: db:wipe bleibt geblockt'

echo
echo "== Erlaubt: gezieltes Stagen, Hooks des Repos, gewöhnliche Migrationen =="
check allow "$F" 'git add datei.txt'                          '74 git add <datei>'
check allow "$F" 'git add src/ tests/'                        '75 git add mit Ordnern'
check allow "$F" 'git add -p'                                 '76 git add -p (interaktiv, gezielt)'
check allow "$F" 'git add -N neu.txt'                         '77 git add -N <datei>'
check allow "$F" 'git commit -m \"x\"'                        '78 git commit ohne -n'
check allow "$F" 'git commit --amend --no-edit'               '79 git commit --amend'
check allow "$F" 'git config core.hooksPath .githooks'        '80 core.hooksPath auf den Hook-Ordner des Repos'
check allow "$F" 'git config user.name \"Test\"'              '81 anderer git config'
check allow "$F" 'git -c user.name=Test commit -m \"x\"'      '82 -c ohne hooksPath'
check allow "$F" 'php artisan migrate'                        '83 artisan migrate'
check allow "$F" 'php artisan migrate:status'                 '84 artisan migrate:status'
check allow "$F" 'php artisan migrate --force'                '85 artisan migrate --force (Rollout)'
check allow "$F" 'alembic upgrade head'                       '86 alembic upgrade head'
check allow "$F" 'alembic downgrade -1'                       '87 alembic downgrade -1'
check allow "$F" 'wp db export sicherung.sql'                 '88 wp db export'
check allow "$F" 'wp cache flush'                             '89 wp cache flush'

echo
echo "== Befunde aus dem Review: Hüllen, Optionen, Schreibweisen =="
check block "$F" 'git config set core.hooksPath /tmp/leer'    '90 git config set (git ≥ 2.46)'
check block "$F" 'git config unset core.hooksPath'            '91 git config unset'
check block "$F" 'git config -f .git/config core.hooksPath /tmp/leer' '92 git config -f <datei>'
check block "$F" 'git config --file .git/config --unset core.hooksPath' '93 --file mit --unset'
check block "$F" 'git config core.hookspath /tmp/leer'        '94 Schlüssel klein geschrieben'
check block "$F" 'git -c CORE.HOOKSPATH=/tmp/leer commit -m \"x\"' '95 -c mit großem Schlüssel'
check block "$F" 'git -ccore.hooksPath=/tmp/leer commit -m \"x\"' '96 -ckey=wert ohne Leerzeichen'
check block "$F" 'git add ./*'                                '97 git add ./*'
check block "$F" 'git add :/*'                                '98 git add :/*'
check block "$F" 'git add . & git status'                     '99 git add . vor einem &'
check block "$F" 'docker compose exec -T app php artisan migrate:fresh' '100 artisan hinter docker compose exec'
check block "$F" 'php -d memory_limit=-1 artisan migrate:fresh' '101 artisan hinter php -d'
check block "$F" './artisan db:wipe'                          '102 ./artisan'
check block "$F" 'uv run alembic downgrade base'              '103 alembic hinter uv run'
check block "$F" 'alembic -c alembic.ini downgrade base'      '104 alembic -c <datei>'
check block "$F" 'wp --path=/var/www/html db reset --yes'     '105 wp --path=… db reset'
check block "$F" 'wp --path /var/www/html db drop'            '106 wp --path <pfad> db drop'
check block "$F" 'git commit -m \"x\" -n'                     '107 -n hinter der Nachricht'

echo
echo "== Keine Fehlalarme: Anführungszeichen, Lesen, Heredoc =="
check allow "$F" 'git commit -m \"docs: --no-verify erklärt\"' '108 --no-verify im Commit-Text'
check allow "$F" 'git commit -m \"fix: Option -n beschrieben\"' '109 -n im Commit-Text'
check allow "$F" "git commit -m 'chore: git add . wird geblockt'" '110 git add . im Commit-Text'
check allow "$F" 'git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat: Guard\n\ngit add . und --no-verify sind geblockt.\nEOF\n)\"' '111 Heredoc-Rumpf ist kein Befehl'
check allow "$F" 'git config core.hooksPath'                  '112 core.hooksPath lesen'
check allow "$F" 'git config --get core.hooksPath'            '113 core.hooksPath mit --get lesen'
check allow "$F" 'git config get core.hooksPath'              '114 git config get'
check allow "$F" 'git config --list'                          '115 git config --list'
check allow "$F" 'git config core.hooksPath .githooks/'       '116 .githooks/ mit Schrägstrich'
check allow "$F" 'git config core.hooksPath ./.githooks'      '117 ./.githooks'
check allow "$F" 'git config --local core.hooksPath .githooks' '118 --local .githooks'
check allow "$F" 'git commit -m \"x\" 2>&1'                   '119 2>&1 ist kein Trenner-Unfall'
check allow "$F" 'grep -r \"alembic downgrade base\" docs/'   '120 Suchmuster in Anführungszeichen'

echo
echo "== Seit 1.1.0: PowerShell-Werkzeug, Zeilenfortsetzung, Unicode-Maskierung, Laufwerkspfade =="
check block "$F" 'git push origin main'                       '121 PowerShell: Push auf main' PowerShell
check block "$F" 'git push --force origin feat/beispiel'      '122 PowerShell: Force-Push' PowerShell
check block "$F" 'Git.exe push -f origin feat/beispiel'       '123 PowerShell: Git.exe groß geschrieben' PowerShell
check block "$F" 'git push origin \\\nmain'                  '124 Bash-Zeilenfortsetzung vor main'
check block "$F" 'git push origin `\nmain'                    '125 PowerShell-Zeilenfortsetzung vor main' PowerShell
check block "$F" 'git push --for\\\nce origin feat/beispiel' '126 Zeilenfortsetzung mitten im Flag'
check block "$F" 'git push origin m\u0061in'                  '127 Unicode-Maskierung im Zweignamen'
check block "$F" 'git push --f\u006frce origin feat/beispiel' '128 Unicode-Maskierung im Flag'
check block "$F" 'git \u0061dd .'                             '129 Unicode-Maskierung im Unterbefehl'
check block "$F" 'rm -rf /mnt/c/Users/jemand'                 '130 rm -rf auf WSL-Pfad'
check block "$F" 'rm -rf /c/Users/jemand'                     '131 rm -rf auf Git-Bash-Laufwerkspfad'
check block "$F" 'Remove-Item -Recurse -Force C:\\Users\\jemand' '132 Remove-Item auf Benutzerordner' PowerShell
check block "$F" 'Remove-Item -Recurse -Force ~'              '133 Remove-Item auf ~' PowerShell
check block "$F" 'rm -r -Force $HOME'                         '134 rm -r -Force $HOME' PowerShell
check block "$F" 'Remove-Item -Path . -Recurse -Force'        '135 Remove-Item -Path .' PowerShell
check block "$F" 'ri -r -fo C:\\'                             '136 ri -r -fo auf Laufwerk (abgekürzt)' PowerShell
check block "$F" 'Remove-Item -Recurse -Force $env:USERPROFILE' '137 Remove-Item auf $env:USERPROFILE' PowerShell
check block "$F" 'Remove-Item -LiteralPath /mnt/c -Recurse -Force' '138 Remove-Item -LiteralPath /mnt/c' PowerShell
check block "$F" 'Remove-Item .\\*, C:\\Temp -Recurse -Force'  '139 Remove-Item mit Kommaliste' PowerShell
check block "$F" 'git push --% --force origin feat/beispiel'  '140 --% (Stop-Parsing) vor --force' PowerShell
check block "$F" 'git commit --no-verify -m \"x\"'            '141 PowerShell: --no-verify' PowerShell
check block "$F" 'php artisan migrate:fresh'                  '142 PowerShell: migrate:fresh' PowerShell
check block "$M" 'git push'                                   '143 PowerShell: Push ohne Ziel auf main' PowerShell

echo
echo "== Erlaubt: PowerShell-Alltag =="
check allow "$F" 'git status --porcelain'                     '144 PowerShell: git status' PowerShell
check allow "$F" 'git push -u origin feat/beispiel'           '145 PowerShell: Feature-Zweig pushen' PowerShell
check allow "$F" 'git push origin `\nfeat/beispiel'           '146 PowerShell-Zeilenfortsetzung auf Feature-Zweig' PowerShell
check allow "$F" 'Remove-Item -Recurse -Force node_modules'   '147 Remove-Item auf Projektordner' PowerShell
check allow "$F" 'Remove-Item -Recurse -Force .\\dist'        '148 Remove-Item auf .\\dist' PowerShell
check allow "$F" 'rm -r node_modules'                         '149 rm -r ohne -Force' PowerShell
check allow "$F" 'Remove-Item -Path .\\build -Recurse -Force'  '150 Remove-Item -Path relativ' PowerShell
check allow "$F" 'Write-Host \"git push --force\"'            '151 Schlagworte als Text in Write-Host' PowerShell
check allow "$F" 'git commit -m \"Gr\u00fc\u00dfe\"'           '152 Unicode-Umlaute im Commit-Text' PowerShell
check allow "$V" 'git push origin main'                       '153 Marker: Push auf main auch aus PowerShell' PowerShell

echo
echo "== Befunde aus dem Review: Wortparameter, Maskierung im Wort, Elternordner, volle Pfade =="
check allow "$F" 'Remove-Item -Force C:\\Temp\\x.log'           '154 -Force ohne -Recurse ist nicht rekursiv' PowerShell
check allow "$F" 'Remove-Item -Force -ErrorAction SilentlyContinue C:\\Temp\\x.log' '155 -ErrorAction ist kein -Recurse' PowerShell
check allow "$F" 'Remove-Item -Recurse -WhatIf ~'              '156 -WhatIf ist kein -Force' PowerShell
check allow "$F" 'rm -Force ~/.npmrc'                         '157 rm -Force einzeln (PowerShell)' PowerShell
check block "$F" 'Remove-Item -Recurse:$true -Force:$true ~'  '158 -Recurse:$true -Force:$true' PowerShell
check block "$F" 'git pu`sh origin main'                      '159 Backtick im Wort (PowerShell)' PowerShell
check block "$F" 'git push --for`ce origin feat/beispiel'     '160 Backtick im Flag (PowerShell)' PowerShell
check block "$F" 'git pu\\sh origin main'                     '161 Backslash im Wort (Bash)'
check block "$F" '\\git push origin main'                     '162 Backslash vor git (Bash)'
check block "$F" 'Remove-Item -Path:C:\\Users\\x -Recurse -Force' '163 -Path:Wert' PowerShell
check block "$F" 'Remove-Item -LiteralPath:~ -Recurse -Force' '164 -LiteralPath:~' PowerShell
check block "$F" 'rm -rf ../../..'                            '165 Elternordner mehrfach'
check block "$F" 'rm -rf ../*'                                '166 Geschwister über ../*'
check block "$F" 'Remove-Item -Recurse -Force ..\\..'         '167 Elternordner (PowerShell)' PowerShell
check block "$F" 'rm -rf $HOME/.config'                       '168 $HOME mit Unterpfad'
check block "$F" 'rm -rf $HOME/*'                             '169 $HOME/*'
check block "$F" 'Remove-Item -Recurse -Force $env:USERPROFILE\\*' '170 $env:USERPROFILE\\*' PowerShell
check block "$F" 'Remove-Item -Recurse -Force $env:USERPROFILE\\Documents' '171 $env:USERPROFILE\\Documents' PowerShell
check block "$F" 'Remove-Item -Recurse -Force $env:HOMEDRIVE$env:HOMEPATH' '172 $env:HOMEDRIVE$env:HOMEPATH' PowerShell
check block "$F" '& \"C:\\Program Files\\Git\\cmd\\git.exe\" push origin main' '173 git über vollen Pfad (PowerShell)' PowerShell
check block "$F" '/usr/bin/git push origin main'              '174 git über vollen Pfad (Bash)'
check block "$F" 'git --% push origin main'                   '175 --% vor dem Unterbefehl' PowerShell
check block "$F" 'command git push origin main'               '176 command git'
check block "$F" 'exec git push --force origin feat/beispiel' '177 exec git'
check block "$F" 'Write-Host \"<<x\"\ngit push origin main'   '178 << in einem PowerShell-String ist kein Heredoc' PowerShell
check block "$F" "rm -rf $F"                                  '179 Arbeitsverzeichnis selbst als absoluter Pfad'
check block "$F" "rm -rf $F/.."                               '180 Arbeitsverzeichnis/..'
check allow "$F" 'Remove-Item -Recurse -Force .\\dist'        '181 relativer Unterordner bleibt erlaubt' PowerShell
check allow "$F" 'echo `git push origin main`'                '182 Backtick-Substitution hinter echo (Bash)'

# hooks.json: die eigentliche Änderung hinter A1 — der Hook hängt an beiden Werkzeugen.
TOTAL=$((TOTAL + 1))
if grep -q '"matcher": "Bash|PowerShell"' "$HERE/hooks.json"; then printf 'ok      %-56s %s\n' '183 hooks.json: Matcher Bash|PowerShell' 'vorhanden'
else printf 'FEHLER  %-56s\n' '183 hooks.json: Matcher Bash|PowerShell fehlt'; FAILED=$((FAILED + 1)); fi

echo
printf 'Fälle: %s   Fehler: %s\n' "$TOTAL" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
echo "Alle Fälle grün."
