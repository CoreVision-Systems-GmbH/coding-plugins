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

# JSON-Nutzlast bauen. $1 = Befehl (bereits JSON-escaped), $2 = Arbeitsverzeichnis.
payload() {
  printf '{"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"Testfall"}}' "$2" "$1"
}

TOTAL=0
FAILED=0

# check <block|allow> <arbeitsverzeichnis> <json-escaped befehl> <beschreibung>
check() {
  local expected="$1" wd="$2" command_text="$3" label="$4"
  local output rc actual

  TOTAL=$((TOTAL + 1))
  output="$(cd "$wd" && payload "$command_text" "$wd" | bash "$GUARD" 2>&1)"
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
printf 'Fälle: %s   Fehler: %s\n' "$TOTAL" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
echo "Alle Fälle grün."
