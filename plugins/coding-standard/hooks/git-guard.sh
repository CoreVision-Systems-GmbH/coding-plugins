#!/usr/bin/env bash
# git-guard.sh — PreToolUse-Hook für das Bash-Tool.
#
# Liest die Hook-Nutzlast als JSON von stdin, holt sich tool_input.command und blockiert
# zerstörende Git- und rm-Befehle. Ohne jq (unter Windows nicht vorhanden), nur mit
# bash-Bordmitteln.
#
# Blockiert -> Exit 0 und eine JSON-Zeile mit permissionDecision "deny".
# Erlaubt   -> Exit 0 ohne Ausgabe.
#
# Der Hook ist ein Geländer, kein Gefängnis: er sieht den Befehlstext, nicht dessen
# Laufzeitverhalten. Er soll den versehentlichen Griff verhindern, nicht den bösen Willen.
#
# Ausnahme: Liegt im Arbeitsverzeichnis der Session (cwd der Nutzlast) eine Datei
# .git-guard-main-ok, sind dort der Push auf main/master und das pauschale Stagen
# (git add -A) erlaubt — gedacht für Doku- und Backup-Repos ohne PR-Fluss (z. B. den
# Notiz-Vault). Alles andere (Force-Push, Löschen von Remote-Zweigen, reset --hard,
# clean -f, branch -D, rm -rf, --no-verify, Umbiegen der Hooks, Datenbanklöscher) bleibt
# auch dort geblockt.
#
# Seit 1.0.0 zusätzlich geblockt: git add ohne Pfadangabe (. / -A / -u / :/ — Dateien mit
# exaktem Pfad stagen, so landen .env, Dumps und Diagnoseskripte nicht im Repo), --no-verify
# bei commit und push sowie das Umbiegen von core.hooksPath (die Prüfhooks des Repos gelten),
# und die Datenbanklöscher migrate:fresh|refresh|reset, db:wipe, alembic downgrade base,
# wp db reset|drop|clean — auch hinter Hüllen wie docker compose exec oder uv run (nur nach
# Bestätigung des Nutzers, von Hand). Anführungszeichen zählen: "--no-verify" in einem
# Commit-Text und der Rumpf eines Heredocs sind Daten, keine Befehle.

set -u
set -f  # Globbing aus: sonst expandiert "rm -rf *" beim Zerlegen zu Dateinamen.

# ---------------------------------------------------------------- Ausgabe

deny() {
  local reason="$1"
  # JSON-Sicherheit: Anführungszeichen, Backslashes und Zeilenumbrüche entfernen.
  reason="${reason//\\/ }"
  reason="${reason//\"/ }"
  reason="${reason//$'\n'/ }"
  reason="${reason//$'\r'/ }"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

# ---------------------------------------------------------------- JSON-Feld lesen

# json_string_value <json> <key>
# Liefert den Wert des ersten String-Feldes mit diesem Namen. Beherrscht \" und \\.
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

# ---------------------------------------------------------------- Hilfen

is_main_branch() {
  case "$1" in
    main|master|refs/heads/main|refs/heads/master) return 0 ;;
    *) return 1 ;;
  esac
}

current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf ''
}

# Arbeitsverzeichnis der Session; wird im Hauptlauf aus der Nutzlast gesetzt.
SESSION_CWD=""

main_push_allowed() {
  local dir="$SESSION_CWD"
  [ -n "$dir" ] || dir="$(pwd 2>/dev/null || printf '')"
  [ -n "$dir" ] || return 1
  dir="${dir//\\//}"   # Windows-Nutzlast: C:\\Users\\… -> C:/Users/…
  [ -f "$dir/.git-guard-main-ok" ]
}

# ---------------------------------------------------------------- git push

check_push() {
  local -a args=("$@")
  local arg refspec dst
  local force=0 lease=0 delete=0 hits_main=0
  local -a positional=()

  for arg in ${args[@]+"${args[@]}"}; do
    case "$arg" in
      --force|--force=*)        force=1 ;;
      --force-with-lease|--force-with-lease=*|--force-if-includes) lease=1 ;;
      --delete)                 delete=1 ;;
      --no-verify)              deny "Blockiert: git push --no-verify umgeht die Prüfhooks des Repos (Geheimnis-Scanner). Befund beheben, nicht umgehen." ;;
      --*)                      : ;;
      -)                        : ;;
      -*)
        # Kurzflaggen, auch gebündelt (-fu, -fq …)
        case "$arg" in *f*) force=1 ;; esac
        case "$arg" in *d*) delete=1 ;; esac
        ;;
      *)                        positional+=("$arg") ;;
    esac
  done

  [ $delete -eq 1 ] && deny "Blockiert: git push --delete löscht einen Zweig auf dem Remote. Zweige werden über den gemergten PR aufgeräumt (Squash-Merge mit --delete-branch) oder nach ausdrücklicher Freigabe des Nutzers von Hand gelöscht."

  # Refspecs sind alle Positionsargumente ab dem zweiten; das erste ist das Remote.
  local i=1
  while [ $i -lt ${#positional[@]} ]; do
    refspec="${positional[$i]}"
    i=$((i + 1))

    case "$refspec" in
      :*) deny "Blockiert: git push origin :zweig löscht den Zweig auf dem Remote. Zweige werden über den gemergten PR aufgeräumt oder nach ausdrücklicher Freigabe des Nutzers von Hand gelöscht." ;;
      +*) force=1; refspec="${refspec#+}" ;;
    esac

    dst="${refspec##*:}"
    dst="${dst#refs/heads/}"
    is_main_branch "$dst" && hits_main=1
  done

  # Ohne Refspec entscheidet der aktuelle Zweig.
  if [ ${#positional[@]} -lt 2 ]; then
    is_main_branch "$(current_branch)" && hits_main=1
  fi

  [ $force -eq 1 ] && deny "Blockiert: Force-Push. Geschichte wird nicht überschrieben — auf einem geteilten Zweig gar nicht, auf dem eigenen Zweig nur mit --force-with-lease und nur nach ausdrücklicher Freigabe des Nutzers. Der Weg auf main führt über einen PR mit grüner CI."

  if [ $lease -eq 1 ] && [ $hits_main -eq 1 ]; then
    deny "Blockiert: --force-with-lease auf main oder master. Auf dem Hauptzweig wird keine Geschichte überschrieben, auch nicht abgesichert. Die Änderung als PR mit grüner CI einbringen."
  fi

  if [ $hits_main -eq 1 ] && ! main_push_allowed; then
    deny "Blockiert: Push direkt auf main oder master. Arbeit gehört auf einen Zweig (feat/… fix/… chore/… docs/…) und von dort per PR mit grüner CI und Squash-Merge nach main. Tags pushen bleibt erlaubt."
  fi

  return 0
}

# ---------------------------------------------------------------- rm -rf

check_rm() {
  local -a args=("$@")
  local arg path expanded cwd
  local recursive=0 force=0
  local -a targets=()

  for arg in ${args[@]+"${args[@]}"}; do
    case "$arg" in
      --recursive) recursive=1 ;;
      --force)     force=1 ;;
      --)          : ;;
      --*)         : ;;
      -*)
        case "$arg" in *r*|*R*) recursive=1 ;; esac
        case "$arg" in *f*)     force=1 ;; esac
        ;;
      *) targets+=("$arg") ;;
    esac
  done

  { [ $recursive -eq 1 ] && [ $force -eq 1 ]; } || return 0

  cwd="$(pwd 2>/dev/null || printf '')"

  for arg in ${targets[@]+"${targets[@]}"}; do
    path="$arg"
    # Schließenden Schrägstrich abstreifen, außer bei "/" selbst.
    while [ "$path" != "/" ] && [ "${path%/}" != "$path" ]; do path="${path%/}"; done

    case "$path" in
      "/"|"/*"|"~"|"."|"*"|"..")
        deny "Blockiert: rm -rf auf $arg. Dieses Ziel löscht das Arbeitsverzeichnis, das Benutzerverzeichnis oder das ganze Dateisystem. Löschungen genau benennen — einzelner Unterordner, relativer Pfad — und bei echtem Bedarf vom Nutzer bestätigen lassen."
        ;;
    esac

    expanded="$path"
    # Die Tilde im Muster ist gewollt wörtlich: Sie steht so im Befehl und wird hier erst
    # selbst durch $HOME ersetzt (SC2088).
    # shellcheck disable=SC2088
    case "$expanded" in
      "~/"*) expanded="${HOME}/${expanded#\~/}" ;;
    esac

    case "$expanded" in
      /*|[A-Za-z]:[\\/]*)
        if [ -n "$cwd" ]; then
          case "$expanded/" in
            "$cwd"/*) : ;;
            *) deny "Blockiert: rm -rf auf den absoluten Pfad $arg außerhalb des Arbeitsverzeichnisses. Innerhalb des Projekts mit relativem Pfad arbeiten; außerhalb nur nach ausdrücklicher Bestätigung des Nutzers." ;;
          esac
        fi
        ;;
    esac
  done

  return 0
}

# ---------------------------------------------------------------- git-Unterbefehle

check_git() {
  local sub="$1"
  shift
  local -a args=("$@")
  local arg

  case "$sub" in
    push)
      check_push ${args[@]+"${args[@]}"}
      ;;

    reset)
      for arg in ${args[@]+"${args[@]}"}; do
        [ "$arg" = "--hard" ] && deny "Blockiert: git reset --hard verwirft nicht committete Arbeit unwiederbringlich. Stattdessen git stash, ein gezieltes git restore <datei> oder ein Revert-Commit. Wenn es wirklich sein muss: vom Nutzer bestätigen lassen."
      done
      ;;

    clean)
      for arg in ${args[@]+"${args[@]}"}; do
        case "$arg" in
          --force) deny "Blockiert: git clean löscht nicht verfolgte Dateien unwiederbringlich, oft auch .env und lokale Konfiguration. Erst git clean -n ansehen, dann die Löschung vom Nutzer bestätigen lassen." ;;
          --*) : ;;
          -*) case "$arg" in *f*) deny "Blockiert: git clean löscht nicht verfolgte Dateien unwiederbringlich, oft auch .env und lokale Konfiguration. Erst git clean -n ansehen, dann die Löschung vom Nutzer bestätigen lassen." ;; esac ;;
        esac
      done
      ;;

    branch)
      for arg in ${args[@]+"${args[@]}"}; do
        case "$arg" in
          --*) : ;;
          -*) case "$arg" in *D*) deny "Blockiert: git branch -D löscht einen Zweig auch dann, wenn er nicht gemergt ist. Zweige werden über den gemergten PR aufgeräumt; ein wirklich verworfener Zweig wird nach ausdrücklicher Freigabe des Nutzers gelöscht." ;; esac ;;
        esac
      done
      ;;

    checkout)
      for arg in ${args[@]+"${args[@]}"}; do
        case "$arg" in
          "."|"./") deny "Blockiert: git checkout -- . verwirft sämtliche Änderungen im Arbeitsbaum. Einzelne Datei gezielt zurücksetzen (git checkout -- <datei>) oder git stash nutzen; ein Rundumschlag nur nach Bestätigung des Nutzers." ;;
        esac
      done
      ;;

    restore)
      for arg in ${args[@]+"${args[@]}"}; do
        case "$arg" in
          -*) : ;;
          "."|"./") deny "Blockiert: git restore . verwirft sämtliche Änderungen im Arbeitsbaum, mit --staged die gesamte Staging-Area. Einzelne Datei gezielt zurücksetzen oder git stash nutzen; ein Rundumschlag nur nach Bestätigung des Nutzers." ;;
        esac
      done
      ;;

    add)
      # Pauschales Stagen nimmt alles mit, auch .env, Dumps und Diagnoseskripte
      # (Fehlermuster F und H). In Repos ohne PR-Fluss (Marker) bleibt es erlaubt.
      main_push_allowed && return 0
      for arg in ${args[@]+"${args[@]}"}; do
        case "$arg" in
          "."|"./"|"*"|"./*"|":/"|":/."|":/*"|":(top)"*|"--all"|"--update"|"--no-ignore-removal")
            deny "Blockiert: git add $arg nimmt alles mit, auch .env, Dumps und Diagnoseskripte. Dateien mit exaktem Pfad stagen (git add <datei> …); git status --short zeigt die Liste vorher." ;;
          --*) : ;;
          -*) case "$arg" in *A*|*u*) deny "Blockiert: git add $arg nimmt alles mit, auch .env, Dumps und Diagnoseskripte. Dateien mit exaktem Pfad stagen (git add <datei> …); git status --short zeigt die Liste vorher." ;; esac ;;
        esac
      done
      ;;

    commit)
      for arg in ${args[@]+"${args[@]}"}; do
        case "$arg" in
          --no-verify) deny "Blockiert: git commit --no-verify umgeht die Prüfhooks des Repos (Geheimnis-Scanner, Formatter). Der Hook ist der Grund, warum der Commit sauber ist — Befund beheben, nicht umgehen." ;;
          --*) : ;;
          -*) case "$arg" in *n*) deny "Blockiert: git commit -n umgeht die Prüfhooks des Repos (Geheimnis-Scanner, Formatter). Befund beheben, nicht umgehen." ;; esac ;;
        esac
      done
      ;;

    config)
      # core.hooksPath darf nur auf die Hooks des Repos zeigen; alles andere schaltet die
      # Prüfhooks ab. Lesen bleibt erlaubt. Formen: `git config core.hooksPath X`,
      # `git config set core.hooksPath X` (git ≥ 2.46), `--unset`, `unset`, `-f <datei>`.
      local key="" value="" unset=0 lesen=0 skip=0
      for arg in ${args[@]+"${args[@]}"}; do
        if [ $skip -eq 1 ]; then skip=0; continue; fi
        case "$arg" in
          --unset|--unset-all|--remove-section) unset=1 ;;
          --get|--get-all|--get-regexp|--list|-l) lesen=1 ;;
          -f|--file|--blob|--type|--default) skip=1 ;;
          --*|-*) : ;;
          set|get|list) [ -z "$key" ] && [ "$arg" = "get" ] && lesen=1 ;;
          unset|unset-all) [ -z "$key" ] && unset=1 ;;
          *) if [ -z "$key" ]; then key="$arg"; elif [ -z "$value" ]; then value="$arg"; fi ;;
        esac
      done
      case "${key,,}" in
        core.hookspath)
          value="${value#./}"
          while [ -n "$value" ] && [ "${value%/}" != "$value" ]; do value="${value%/}"; done
          if [ $unset -eq 1 ]; then
            deny "Blockiert: git config core.hooksPath entfernen schaltet die Prüfhooks des Repos ab. Erlaubt ist nur der Hook-Ordner des Repos: git config core.hooksPath .githooks."
          fi
          if [ $lesen -eq 0 ] && [ -n "$value" ] && [ "$value" != ".githooks" ]; then
            deny "Blockiert: git config core.hooksPath biegt die Prüfhooks des Repos um. Erlaubt ist nur der Hook-Ordner des Repos: git config core.hooksPath .githooks."
          fi
          ;;
      esac
      ;;
  esac

  return 0
}

# ---------------------------------------------------------------- Datenbanklöscher

# check_db <werkzeug> <args…> — Befehle, die eine ganze Datenbank leeren. Führende Optionen
# (`alembic -c alembic.ini …`, `wp --path=… …`) werden übersprungen.
check_db() {
  local tool="$1"
  shift
  local -a args=("$@")
  local -a rest=()
  local arg skip=0
  for arg in ${args[@]+"${args[@]}"}; do
    if [ $skip -eq 1 ]; then skip=0; continue; fi
    case "$arg" in
      -c|-n|-x|--name|--path|--url|--user) [ ${#rest[@]} -eq 0 ] && { skip=1; continue; } ;;
      -*) [ ${#rest[@]} -eq 0 ] && continue ;;
    esac
    rest+=("$arg")
  done
  local first="${rest[0]:-}" second="${rest[1]:-}"

  case "$tool" in
    artisan)
      case "$first" in
        migrate:fresh|migrate:refresh|migrate:reset|db:wipe)
          deny "Blockiert: php artisan $first leert die Datenbank, auf die die .env zeigt — auch eine Dev-Instanz mit Testdaten oder, bei falscher .env, Produktion. Nur der Nutzer führt das aus, nach Blick auf DB_HOST; für Tests reicht RefreshDatabase." ;;
      esac
      ;;
    alembic)
      if [ "$first" = "downgrade" ] && [ "$second" = "base" ]; then
        deny "Blockiert: alembic downgrade base nimmt alle Migrationen zurück und leert die Datenbank. Nur der Nutzer führt das aus, nach Blick auf die Datenbank-URL."
      fi
      ;;
    wp)
      if [ "$first" = "db" ]; then
        case "$second" in
          reset|drop|clean) deny "Blockiert: wp db $second leert oder löscht die Datenbank der Site. Nur der Nutzer führt das aus, nach Sicherung." ;;
        esac
      fi
      ;;
  esac

  return 0
}

# ---------------------------------------------------------------- Teilbefehl prüfen

# tokenize <segment> — füllt das Feld `tokens`, Anführungszeichen-fest: "kein -n" ist ein
# Token, kein Flag. Ein Token, das ganz in Anführungszeichen stand und mit - beginnt, bekommt
# ein Hochkomma vorangestellt, damit es kein Flag mehr ist (Commit-Text, kein Befehl).
tokenize() {
  local s="$1" i n ch tok="" quote="" quoted=0
  tokens=()
  n=${#s}
  i=0
  while [ $i -lt $n ]; do
    ch="${s:$i:1}"
    i=$((i + 1))
    if [ -n "$quote" ]; then
      if [ "$ch" = "$quote" ]; then quote=""
      elif [ "$ch" = "\\" ] && [ "$quote" = '"' ] && [ $i -lt $n ]; then tok="$tok${s:$i:1}"; i=$((i + 1))
      else tok="$tok$ch"; fi
      continue
    fi
    case "$ch" in
      '"'|"'") quote="$ch"; quoted=1 ;;
      ' '|$'\t')
        if [ -n "$tok" ] || [ $quoted -eq 1 ]; then
          [ $quoted -eq 1 ] && [ "${tok:0:1}" = "-" ] && tok="'$tok"
          tokens+=("$tok"); tok=""; quoted=0
        fi ;;
      '(') [ -z "$tok" ] || tok="$tok$ch" ;;   # führende Klammer einer Unterschale abstreifen
      *) tok="$tok$ch" ;;
    esac
  done
  if [ -n "$tok" ] || [ $quoted -eq 1 ]; then
    [ $quoted -eq 1 ] && [ "${tok:0:1}" = "-" ] && tok="'$tok"
    tokens+=("$tok")
  fi
}

check_segment() {
  local segment="$1"
  local -a tokens=()
  local word i sub
  local -a args=()

  [ -n "${segment//[[:space:]]/}" ] || return 0

  tokenize "$segment"
  [ ${#tokens[@]} -gt 0 ] || return 0

  # Führende Hüllen abstreifen: sudo, ENV-Zuweisungen, Schleifen-Schlüsselwörter.
  i=0
  while [ $i -lt ${#tokens[@]} ]; do
    case "${tokens[$i]}" in
      sudo|time|env|nohup|do|then|else|'('|'{'|'!') i=$((i + 1)) ;;
      *=*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ $i -lt ${#tokens[@]} ] || return 0

  case "${tokens[$i]}" in
    git)
      i=$((i + 1))
      # Globale git-Optionen überspringen, bis der Unterbefehl kommt. Ein -c mit
      # core.hooksPath biegt die Prüfhooks für diesen einen Aufruf um (auch als -ckey=wert,
      # --config-env=… und in beliebiger Schreibung des Schlüssels).
      while [ $i -lt ${#tokens[@]} ]; do
        word="${tokens[$i],,}"
        case "$word" in
          -c)
            case "${tokens[$((i + 1))]:-}" in
              [Cc][Oo][Rr][Ee].[Hh][Oo][Oo][Kk][Ss][Pp][Aa][Tt][Hh]*) deny "Blockiert: git -c core.hooksPath=… umgeht die Prüfhooks des Repos für diesen Aufruf. Befund beheben, nicht umgehen." ;;
            esac
            i=$((i + 2)) ;;
          -c*core.hookspath*|--config-env=core.hookspath=*) deny "Blockiert: git -c core.hooksPath=… umgeht die Prüfhooks des Repos für diesen Aufruf. Befund beheben, nicht umgehen." ;;
          -c*|--config-env=*) i=$((i + 1)) ;;
          -C) i=$((i + 2)) ;;
          --git-dir=*|--work-tree=*|--namespace=*|--no-pager|-p|--paginate|--literal-pathspecs|--no-replace-objects) i=$((i + 1)) ;;
          *) break ;;
        esac
      done
      [ $i -lt ${#tokens[@]} ] || return 0
      sub="${tokens[$i]}"
      args=("${tokens[@]:$((i + 1))}")
      check_git "$sub" ${args[@]+"${args[@]}"}
      ;;
    rm)
      args=("${tokens[@]:$((i + 1))}")
      check_rm ${args[@]+"${args[@]}"}
      ;;
  esac

  # Datenbanklöscher: das Werkzeug kann hinter Hüllen stehen (docker compose exec … php
  # artisan …, uv run alembic …, php -d … artisan …) — deshalb an jeder Stelle des Segments.
  local j=0
  while [ $j -lt ${#tokens[@]} ]; do
    case "${tokens[$j]}" in
      artisan|*/artisan)
        args=("${tokens[@]:$((j + 1))}")
        check_db artisan ${args[@]+"${args[@]}"}
        break ;;
      alembic|wp)
        args=("${tokens[@]:$((j + 1))}")
        check_db "${tokens[$j]}" ${args[@]+"${args[@]}"}
        break ;;
    esac
    j=$((j + 1))
  done

  return 0
}

# strip_heredocs <text> — entfernt die Rümpfe von Heredocs (<<EOF … EOF): Sie sind Daten
# (Commit-Texte, Dateiinhalte), keine Befehle — sonst blockte `git add . wird geblockt` als
# Zeile eines Commit-Rumpfs den ganzen Commit.
strip_heredocs() {
  local text="$1" line marker="" out=""
  while IFS= read -r line; do
    if [ -n "$marker" ]; then
      [ "${line//[[:space:]]/}" = "$marker" ] && marker=""
      continue
    fi
    out="$out$line"$'\n'
    case "$line" in
      *"<<"*)
        marker="${line##*<<}"
        case "$marker" in "<"*) marker=""; continue ;; esac   # <<< ist ein Here-String
        marker="${marker#-}"
        marker="${marker#"${marker%%[! ]*}"}"   # führende Leerzeichen
        marker="${marker%%[[:space:]]*}"
        marker="${marker//\'/}"
        marker="${marker//\"/}"
        marker="${marker%%\)*}"
        ;;
    esac
  done <<< "$text"
  printf '%s' "$out"
}

# ---------------------------------------------------------------- Hauptlauf

payload="$(cat)"
command_text="$(json_string_value "$payload" "command")" || exit 0
[ -n "$command_text" ] || exit 0
SESSION_CWD="$(json_string_value "$payload" "cwd")" || SESSION_CWD=""

# Heredoc-Rümpfe sind Daten, keine Befehle. Danach in Teilbefehle zerlegen: && || ; | & und
# Zeilenumbruch (ein einzelnes & trennt einen Hintergrundbefehl; 2>&1 ergibt harmlose Reste).
split="$(strip_heredocs "$command_text")"
split="${split//&&/$'\n'}"
split="${split//||/$'\n'}"
split="${split//;/$'\n'}"
split="${split//|/$'\n'}"
split="${split//&/$'\n'}"

while IFS= read -r segment; do
  check_segment "$segment"
done <<< "$split"

exit 0
