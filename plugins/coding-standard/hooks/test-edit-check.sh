#!/usr/bin/env bash
# test-edit-check.sh — prüft edit-check.sh mit Beispiel-Nutzlasten und Werkzeug-Attrappen.
#
# Aufruf:   bash plugins/coding-standard/hooks/test-edit-check.sh
# Ergebnis: Exit 0, wenn alle Fälle grün sind, sonst Exit 1.
#
# php, pint, ruff, shellcheck, node, eslint und python3 sind Attrappen in einem eigenen PATH,
# damit der Test auf jedem Rechner gleich läuft; bash -n ist echt. Geprüft werden: nur
# erklärte Repos, Befund je Werkzeug als JSON mit additionalContext, keine Ausgabe ohne
# Befund, fehlendes Werkzeug schweigt, WindowsApps-Alias, Windows-Pfade, JSON-Sicherheit,
# große Nutzlast, Notausgang.

# Prüfmuster `[ … ]; behaupte "…" $?`: $? soll das Ergebnis der Bedingung sein (SC2319).
# shellcheck disable=SC2319

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/edit-check.sh"
BASH_BIN="$BASH"

fehler=0
behaupte() { if [ "$2" -eq 0 ]; then echo "ok     $1"; else echo "FEHLER $1"; fehler=$((fehler + 1)); fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- Attrappen: reagieren auf den Inhalt der Datei, nicht auf echte Syntax.
mkdir -p "$tmp/bin"
for w in cat head grep printf tr cut env; do
    p="$(command -v "$w")" || continue
    printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$p" > "$tmp/bin/$w"; chmod +x "$tmp/bin/$w"
done
# Der Hook ruft bash selbst nur über den PATH auf, deshalb auch bash weiterreichen.
printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$BASH_BIN" > "$tmp/bin/bash"; chmod +x "$tmp/bin/bash"

stub() { printf '#!%s\n%s\n' "$BASH_BIN" "$2" > "$tmp/bin/$1"; chmod +x "$tmp/bin/$1"; }
stub php 'f="${@: -1}"; if grep -q PARSE_ERROR "$f"; then echo "PHP Parse error: syntax error in $f on line 3"; exit 255; fi; echo "No syntax errors detected in $f"'
# Die ruff-Attrappe gibt Anführungszeichen, einen Backslash und ein ESC-Zeichen aus — genau
# das, was json_escape abfangen muss.
stub ruff 'f="${@: -1}"; case "$1" in check) if grep -q undefined_name "$f"; then printf "%s:2:1: F821 Undefined name \"undefined_name\" in C:\\\\tmp \033[31mrot\033[0m\n" "$f"; exit 1; fi;; format) if grep -q UNFORMATTED "$f"; then echo "Would reformat: $f"; exit 1; fi;; esac; exit 0'
# SC2034 ist bei echtem shellcheck eine Warnung (SC2086 nur info — mit -S warning stumm).
stub shellcheck 'f="${@: -1}"; if grep -q SC2034_TRIGGER "$f"; then echo "In $f line 2: SC2034 (warning): unbenutzt appears unused"; exit 1; fi; exit 0'
stub pint 'f="${@: -1}"; if grep -q UNFORMATTED_PHP "$f"; then echo "FAIL $f psr12"; exit 1; fi; exit 0'
stub node 'if [ "$1" = "--check" ] && grep -q SYNTAX_ERROR_JS "$2"; then echo "$2:1 SyntaxError: Unexpected token"; exit 1; fi; exit 0'
stub eslint 'f="${@: -1}"; if grep -q ESLINT_TRIGGER "$f"; then echo "$f 1:1 error no-undef"; exit 1; fi; exit 0'
stub python3 'if [ "$1" = "-m" ] && [ "$2" = "json.tool" ] && grep -q JSON_BROKEN "$3"; then echo "Expecting value: line 1 column 1 (char 0)"; exit 1; fi; exit 0'
# Der App-Execution-Alias von Windows: antwortet mit Store-Hinweis und Exit 9009.
mkdir -p "$tmp/WindowsApps"
printf '#!%s\necho "Python was not found; run without arguments to install from the Microsoft Store"; exit 9009\n' "$BASH_BIN" > "$tmp/WindowsApps/python3"; chmod +x "$tmp/WindowsApps/python3"

# --- Repos: eines erklärt (Marker), eines nicht.
erklaert="$tmp/erklaert"; mkdir -p "$erklaert"; printf 'stack: script\n' > "$erklaert/.coding-standard"
fremd="$tmp/fremd"; mkdir -p "$fremd"

payload() { # <datei> — JSON-Nutzlast eines PostToolUse für Edit
    printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"},"tool_response":{"success":true}}' "$2" "$1"
}

lauf() { # <projekt> <datei> [ENV=…] — Hook mit Attrappen-PATH ausführen, Ausgabe zurück
    local proj="$1" datei="$2"; shift 2
    payload "$datei" "$proj" | env -i PATH="$tmp/bin" HOME="$tmp" CLAUDE_PROJECT_DIR="$proj" "$@" "$BASH_BIN" "$HOOK" 2>&1
}

# --- Fälle
printf '<?php\necho 1;\n' > "$erklaert/gut.php"
printf '<?php\nPARSE_ERROR\n' > "$erklaert/schlecht.php"
printf 'x = 1\n' > "$erklaert/gut.py"
printf 'x = 1\nprint(undefined_name)\n' > "$erklaert/schlecht.py"
printf 'x = 1  # UNFORMATTED\n' > "$erklaert/unformatiert.py"
printf '#!/usr/bin/env bash\necho ok\n' > "$erklaert/gut.sh"
printf '#!/usr/bin/env bash\nif [ 1 ]; then\n' > "$erklaert/kaputt.sh"
printf '#!/usr/bin/env bash\nunbenutzt=1 # SC2034_TRIGGER\n' > "$erklaert/warnung.sh"
printf 'hallo\n' > "$erklaert/notiz.txt"
printf '<?php\nUNFORMATTED_PHP\n' > "$erklaert/unformatiert.php"
printf 'SYNTAX_ERROR_JS\n' > "$erklaert/kaputt.js"
printf 'const a = 1; // ESLINT_TRIGGER\n' > "$erklaert/schlecht.ts"
printf 'JSON_BROKEN\n' > "$erklaert/kaputt.json"
printf '{}\n' > "$erklaert/gut.json"
printf '<?php\nPARSE_ERROR\n' > "$fremd/schlecht.php"

out="$(lauf "$erklaert" "$erklaert/gut.php")"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ]; behaupte "gute PHP-Datei: keine Ausgabe, Exit 0" $?

out="$(lauf "$erklaert" "$erklaert/schlecht.php")"; rc=$?
[ $rc -eq 0 ] && printf '%s' "$out" | grep -q '"hookEventName":"PostToolUse"' && printf '%s' "$out" | grep -q 'additionalContext' \
    && printf '%s' "$out" | grep -q 'PHP Parse error'; behaupte "PHP-Syntaxfehler: Befund als additionalContext, Exit 0" $?
printf '%s' "$out" | grep -q 'schlecht.php'; behaupte "Befund nennt die Datei" $?
printf '%s' "$out" | grep -q '== php -l'; behaupte "Befund nennt das Werkzeug" $?

out="$(lauf "$erklaert" "$erklaert/schlecht.py")"
printf '%s' "$out" | grep -q 'F821'; behaupte "Python: undefinierter Name wird gemeldet" $?
out="$(lauf "$erklaert" "$erklaert/unformatiert.py")"
printf '%s' "$out" | grep -q 'Would reformat'; behaupte "Python: fehlende Formatierung wird gemeldet" $?
out="$(lauf "$erklaert" "$erklaert/gut.py")"
[ -z "$out" ]; behaupte "gute Python-Datei: keine Ausgabe" $?

out="$(lauf "$erklaert" "$erklaert/kaputt.sh")"
printf '%s' "$out" | grep -q '== bash -n'; behaupte "Shell: Syntaxfehler über bash -n" $?
out="$(lauf "$erklaert" "$erklaert/warnung.sh")"
printf '%s' "$out" | grep -q 'SC2034'; behaupte "Shell: shellcheck-Warnung wird gemeldet" $?
out="$(lauf "$erklaert" "$erklaert/gut.sh")"
[ -z "$out" ]; behaupte "gute Shell-Datei: keine Ausgabe" $?

out="$(lauf "$erklaert" "$erklaert/unformatiert.php")"
printf '%s' "$out" | grep -q '== pint --test'; behaupte "PHP: Pint-Befund wird gemeldet" $?
out="$(lauf "$erklaert" "$erklaert/kaputt.js")"
printf '%s' "$out" | grep -q '== node --check'; behaupte "JavaScript: Syntaxfehler über node --check" $?
out="$(lauf "$erklaert" "$erklaert/schlecht.ts")"
printf '%s' "$out" | grep -q '== eslint'; behaupte "TypeScript: ESLint-Befund wird gemeldet" $?
out="$(lauf "$erklaert" "$erklaert/kaputt.json")"
printf '%s' "$out" | grep -q '== json'; behaupte "JSON: ungültige Datei wird gemeldet" $?
out="$(lauf "$erklaert" "$erklaert/gut.json")"
[ -z "$out" ]; behaupte "gültige JSON-Datei: keine Ausgabe" $?

# Windows ohne Python: der Alias unter WindowsApps steht vorn im PATH — kein falscher Befund.
out="$(payload "$erklaert/kaputt.json" "$erklaert" | env -i PATH="$tmp/WindowsApps:$tmp/bin" HOME="$tmp" CLAUDE_PROJECT_DIR="$erklaert" "$BASH_BIN" "$HOOK" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ]; behaupte "WindowsApps-Alias für python3 wird übersprungen" $?

out="$(lauf "$erklaert" "$erklaert/notiz.txt")"
[ -z "$out" ]; behaupte "unbekannte Endung: keine Ausgabe" $?

out="$(lauf "$fremd" "$fremd/schlecht.php")"
[ -z "$out" ]; behaupte "nicht erklärtes Repo: keine Ausgabe, auch bei Fehler" $?

out="$(lauf "$erklaert" "$erklaert/schlecht.php" CODING_STANDARD_OFF=1)"
[ -z "$out" ]; behaupte "Notausgang CODING_STANDARD_OFF=1: keine Ausgabe" $?

# Fehlendes Werkzeug: php aus dem PATH nehmen — der Hook schweigt, statt zu scheitern.
mv "$tmp/bin/php" "$tmp/php.weg"
out="$(lauf "$erklaert" "$erklaert/schlecht.php")"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ]; behaupte "fehlendes Werkzeug: keine Ausgabe, Exit 0" $?
mv "$tmp/php.weg" "$tmp/bin/php"

# Windows-Pfad mit Backslashes in der Nutzlast (so schickt Claude Code ihn unter Windows).
win="$(printf '%s' "$erklaert/schlecht.php" | sed 's#/#\\\\#g')"
out="$(lauf "$erklaert" "$win")"
printf '%s' "$out" | grep -q 'PHP Parse error'; behaupte "Windows-Pfad mit Backslashes wird verstanden" $?

# JSON-Sicherheit: Anführungszeichen, Backslash, ESC und Zeilenumbrüche in der Werkzeugausgabe
# bleiben gültiges JSON — mit dem Befund darin, ohne das ESC-Zeichen.
py=""
for k in python3 python; do
    p="$(command -v "$k" 2>/dev/null)" || continue
    case "$p" in *WindowsApps*) continue ;; esac
    "$p" -c 'import json' >/dev/null 2>&1 && { py="$p"; break; }
done
if [ -n "$py" ]; then
    out="$(lauf "$erklaert" "$erklaert/schlecht.py")"
    printf '%s' "$out" | "$py" -c 'import json,sys; d=json.load(sys.stdin); t=d["hookSpecificOutput"]["additionalContext"]; assert "F821" in t; assert "Undefined name \"undefined_name\" in C:\\tmp" in t, t; assert "\033" not in t'
    behaupte "Ausgabe ist gültiges JSON mit Anführungszeichen und Backslash, ohne ESC" $?
    # Eine sehr lange Zeile wird gekappt, damit der Kontext nicht aus einer Zeile besteht.
    printf 'x = 1\nprint(undefined_name)  # %s\n' "$(head -c 5000 /dev/zero | tr '\0' 'a')" > "$erklaert/lang.py"
    out="$(lauf "$erklaert" "$erklaert/lang.py")"
    printf '%s' "$out" | "$py" -c 'import json,sys; d=json.load(sys.stdin); t=d["hookSpecificOutput"]["additionalContext"]; assert all(len(z) <= 2100 for z in t.splitlines()), max(len(z) for z in t.splitlines())'
    behaupte "lange Zeilen werden auf 2000 Zeichen gekappt" $?
else
    echo "skip   JSON-Prüfung (kein Python)"
fi

# Große Nutzlast: tool_response trägt den ganzen Dateiinhalt — der Hook darf nicht quadratisch
# darüber laufen. Eine 1-MB-Nutzlast muss deutlich unter dem Hook-Timeout (30 s) bleiben.
gross="$(head -c 1000000 /dev/zero | tr '\0' 'x')"
start=$(date +%s)
out="$(printf '{"session_id":"s1","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"a"},"tool_response":{"content":"%s"}}' "$erklaert" "$erklaert/schlecht.php" "$gross" \
    | env -i PATH="$tmp/bin" HOME="$tmp" CLAUDE_PROJECT_DIR="$erklaert" "$BASH_BIN" "$HOOK" 2>&1)"
dauer=$(( $(date +%s) - start ))
printf '%s' "$out" | grep -q 'PHP Parse error' && [ "$dauer" -le 5 ]; behaupte "1-MB-Nutzlast: Befund in unter 5 s (gemessen: ${dauer} s)" $?

# Nutzlast ohne file_path (z. B. anderes Werkzeug): schweigen.
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | env -i PATH="$tmp/bin" CLAUDE_PROJECT_DIR="$erklaert" "$BASH_BIN" "$HOOK" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ -z "$out" ]; behaupte "Nutzlast ohne file_path: keine Ausgabe" $?

echo
if [ "$fehler" -eq 0 ]; then echo "Alle Fälle grün."; else echo "Fehler: $fehler"; exit 1; fi
