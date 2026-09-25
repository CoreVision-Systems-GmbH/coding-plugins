#!/usr/bin/env bash
# edit-check.sh — PostToolUse-Hook für Edit, Write und MultiEdit.
#
# Prüft die gerade geänderte Datei sofort auf Syntax und Format und meldet Befunde als
# Zusatzkontext an Claude — in Sekunden, nicht erst beim nächsten `check`. Der Hook ändert
# nichts (auch keine Formatierung: eine Datei, die sich hinter dem Rücken des Edit-Tools
# ändert, bricht dessen nächsten Aufruf) und bricht nichts ab; er ist Rückmeldung, kein Tor.
#
# Läuft nur in erklärten Repos (.claude/settings.json mit coding-standard@corevision oder
# Markerdatei .coding-standard) und nur mit Werkzeugen, die im Repo oder im PATH vorhanden
# sind. Fehlt ein Werkzeug, schweigt der Hook — die CI prüft ohnehin.
#
# Je Endung:
#   .php                 php -l; vendor/bin/pint --test (nicht bei .blade.php)
#   .py                  ruff check --select E9,F (Syntax, undefinierte Namen); ruff format --check
#   .sh                  bash -n; shellcheck -S warning
#   .js .mjs .cjs        node --check; ESLint des Repos, falls vorhanden
#   .ts .tsx .jsx        ESLint des Repos, falls vorhanden
#   .json                python -m json.tool
#
# Notausgang: CODING_STANDARD_OFF=1 in der Umgebung.
#
# Bekannte Lücke: Ein Pfad, den die Nutzlast als \uXXXX escapet, wird nicht aufgelöst — die
# Datei gilt dann als nicht vorhanden, und der Hook schweigt. Claude Code schickt Pfade als
# rohes UTF-8, deshalb bleibt das ohne Folge.

set -u
set -f

# ---------------------------------------------------------------- JSON lesen (wie git-guard.sh)

json_string_value() {
  local json="$1" key="$2"
  local rest char esc out

  rest="${json#*\"$key\"}"
  [ "$rest" = "$json" ] && return 1
  rest="${rest#*:}"
  while :; do
    char="${rest:0:1}"
    case "$char" in
      ' '|$'\t'|$'\n'|$'\r') rest="${rest:1}" ;;
      *) break ;;
    esac
  done
  [ "${rest:0:1}" = '"' ] || return 1
  rest="${rest:1}"
  out=""
  while [ -n "$rest" ]; do
    char="${rest:0:1}"
    rest="${rest:1}"
    if [ "$char" = "\\" ]; then
      esc="${rest:0:1}"
      rest="${rest:1}"
      case "$esc" in
        n) out="$out"$'\n' ;;
        t) out="$out"$'\t' ;;
        r|b|f) ;;
        u) rest="${rest:4}"; out="$out?" ;;
        *) out="$out$esc" ;;
      esac
    elif [ "$char" = '"' ]; then
      printf '%s' "$out"
      return 0
    else
      out="$out$char"
    fi
  done
  return 1
}

# ---------------------------------------------------------------- Ausgabe

# json_escape <text> — für einen JSON-String: Backslash, Anführungszeichen, Zeilenumbruch, Tab.
# Andere Steuerzeichen (ESC aus Farbcodes, FF, BS) fliegen raus — sie machen das JSON ungültig.
json_escape() {
  local s="$1"
  s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\r'/}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

befunde=""
befund() { # <werkzeug> <ausgabe>
  local kopf="$1" text="$2"
  # Höchstens 25 Zeilen zu je 2000 Zeichen je Werkzeug — der Rest steht ohnehin im
  # nächsten `check` (eine minifizierte JS-Zeile wäre sonst der ganze Kontext).
  text="$(printf '%s\n' "$text" | head -n 25 | cut -c1-2000)"
  befunde="${befunde}== ${kopf}
${text}
"
}

# ---------------------------------------------------------------- Werkzeuge finden

proj="${CLAUDE_PROJECT_DIR:-$PWD}"

# werkzeug <name> — gibt den Pfad aus: erst im Repo (vendor/bin, node_modules/.bin, .venv),
# dann im PATH. Leer, wenn nichts da ist.
werkzeug() {
  local name="$1" kandidat
  for kandidat in \
    "$proj/vendor/bin/$name" "$proj/vendor/bin/$name.bat" \
    "$proj/node_modules/.bin/$name" \
    "$proj/.venv/bin/$name" "$proj/.venv/Scripts/$name.exe"; do
    [ -x "$kandidat" ] && { printf '%s' "$kandidat"; return 0; }
  done
  kandidat="$(command -v "$name" 2>/dev/null)" || return 1
  # Windows ohne Python: command -v findet den App-Execution-Alias unter WindowsApps. Der
  # gibt nur einen Store-Hinweis aus und endet mit 9009 — das wäre nach jedem JSON-Edit ein
  # falscher Befund.
  case "$kandidat" in *WindowsApps*) return 1 ;; esac
  printf '%s' "$kandidat"
}

# lauf <kopf> <befehl…> — führt aus; bei Exit ≠ 0 wird die Ausgabe zum Befund. Ohne
# Farbcodes: ESC-Sequenzen aus FORCE_COLOR würden das JSON der Ausgabe ungültig machen.
lauf() {
  local kopf="$1"; shift
  local ausgabe
  if ! ausgabe="$(env -u FORCE_COLOR -u CLICOLOR_FORCE NO_COLOR=1 "$@" 2>&1)"; then
    befund "$kopf" "$ausgabe"
  fi
}

# ---------------------------------------------------------------- Hauptlauf

[ "${CODING_STANDARD_OFF:-0}" = "1" ] && exit 0

payload="$(cat)"
# Nur der Kopf der Nutzlast wird geparst: tool_input.file_path steht in den ersten paar
# hundert Bytes, tool_response trägt den ganzen Dateiinhalt — und der Parser ist quadratisch
# (1 MB Nutzlast wären Sekunden). Ist der Pfad im Kopf angeschnitten, hilft der ganze Text.
datei="$(json_string_value "${payload:0:16384}" "file_path")" \
  || datei="$(json_string_value "$payload" "file_path")" \
  || exit 0
[ -n "$datei" ] || exit 0
datei="${datei//\\//}"   # Windows-Nutzlast: C:\\Users\\… -> C:/Users/…
[ -f "$datei" ] || exit 0

# Nur in erklärten Repos.
aktiv=0
if [ -f "$proj/.claude/settings.json" ] && grep -q 'coding-standard@corevision' "$proj/.claude/settings.json" 2>/dev/null; then
  aktiv=1
fi
[ -f "$proj/.coding-standard" ] && aktiv=1
[ "$aktiv" -eq 1 ] || exit 0

name="${datei##*/}"
case "$name" in
  *.blade.php)
    if w="$(werkzeug php)"; then lauf "php -l" "$w" -l "$datei"; fi
    ;;
  *.php)
    if w="$(werkzeug php)"; then lauf "php -l" "$w" -l "$datei"; fi
    if w="$(werkzeug pint)"; then lauf "pint --test" "$w" --test "$datei"; fi
    ;;
  *.py)
    if w="$(werkzeug ruff)"; then
      lauf "ruff check" "$w" check --select E9,F --no-cache "$datei"
      lauf "ruff format --check" "$w" format --check --no-cache "$datei"
    fi
    ;;
  *.sh)
    lauf "bash -n" bash -n "$datei"
    if w="$(werkzeug shellcheck)"; then lauf "shellcheck" "$w" -S warning "$datei"; fi
    ;;
  *.js|*.mjs|*.cjs)
    if w="$(werkzeug node)"; then lauf "node --check" "$w" --check "$datei"; fi
    if w="$(werkzeug eslint)"; then lauf "eslint" "$w" --no-fix "$datei"; fi
    ;;
  *.ts|*.tsx|*.jsx)
    if w="$(werkzeug eslint)"; then lauf "eslint" "$w" --no-fix "$datei"; fi
    ;;
  *.json)
    if w="$(werkzeug python3)" || w="$(werkzeug python)"; then lauf "json" "$w" -m json.tool "$datei"; fi
    ;;
esac

[ -n "$befunde" ] || exit 0

text="Prüfung der geänderten Datei ${name}: Befunde (beheben, bevor der nächste Schritt beginnt — der Hook ändert nichts).
${befunde}"
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$(json_escape "$text")"
exit 0
