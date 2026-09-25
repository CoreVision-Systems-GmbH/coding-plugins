#!/usr/bin/env bash
# smoke.sh — Rauchtest nach dem Start: ruft die Routen aus deploy/smoke.txt im laufenden
# Verbund auf und prüft Status, Antwortzeit und Pflichtinhalt.
#
# Aufruf:   deploy/smoke.sh [-p <compose-projekt>] [--dry-run]
#           von deploy/update.sh (rot = Abbruch mit Rückweg) und deploy/dev.sh up (rot = Warnung)
# Ändert:   nichts — nur GET-Aufrufe aus dem App-Container heraus. --dry-run zeigt die Liste.
# Rückweg:  keiner nötig.
#
# deploy/smoke.txt, je Zeile:  <pfad> <status> <sekunden> [<pflichtinhalt …>]   (# = Kommentar)
# Der Aufruf läuft im App-Container gegen 127.0.0.1:8080 (curl, sonst wget aus BusyBox) —
# der Verbund veröffentlicht keinen Port. Die Zeit wird außen gemessen, den Docker-Aufruf
# (0,3 bis 1 s für compose exec) inklusive: Budgets mit Reserve setzen, es ist kein
# Millisekundenmaß. Ein # zählt als Kommentar am Zeilenanfang oder nach Leerraum.

set -euo pipefail
set -f                 # kein Globbing: ein Pflichtinhalt mit * oder ? bleibt Text
export LC_NUMERIC=C    # $EPOCHREALTIME mit Punkt, egal welche Locale per SSH ankommt

cd "$(dirname "$0")/.."

projekt=""
trocken=0
while [ $# -gt 0 ]; do
    case "$1" in
        -p) projekt="$2"; shift 2 ;;
        --dry-run) trocken=1; shift ;;
        --help|-h) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unbekanntes Argument: $1 (deploy/smoke.sh --help)" >&2; exit 2 ;;
    esac
done

liste="deploy/smoke.txt"
[ -f "$liste" ] || { echo "FEHLER: $liste fehlt — ohne Routen kein Rauchtest." >&2; exit 2; }

compose() {
    if [ -n "$projekt" ]; then docker compose -p "$projekt" "$@"; else docker compose "$@"; fi
}

# abruf <pfad> <sekunden> — erste Zeile: HTTP-Status (000 bei Zeitüberschreitung), Rest: Antwort.
# </dev/null ist Pflicht: compose exec hängt sonst stdin an und frisst den Rest der Liste,
# aus der die Schleife liest — es liefe nur die erste Route.
abruf() {
    compose exec -T app sh -c '
        if command -v curl >/dev/null 2>&1; then
            curl -s -o /tmp/smoke.body -w "%{http_code}" --max-time "$2" "http://127.0.0.1:8080$1" || true
            echo
        else
            wget -q -O /tmp/smoke.body -S -T "$2" "http://127.0.0.1:8080$1" 2>/tmp/smoke.head || true
            status="$(sed -n "s/^ *HTTP\/[0-9.]* \([0-9][0-9][0-9]\).*/\1/p" /tmp/smoke.head | tail -1)"
            echo "${status:-000}"
        fi
        cat /tmp/smoke.body 2>/dev/null || true
    ' sh "$1" "$2" </dev/null
}

rot=0
n=0
[ "$trocken" -eq 1 ] || printf '== Rauchtest (%s)\n' "$liste"
while IFS= read -r zeile || [ -n "$zeile" ]; do
    case "$zeile" in \#*) continue ;; esac
    zeile="${zeile%%[[:space:]]#*}"
    [ -n "${zeile//[[:space:]]/}" ] || continue
    # shellcheck disable=SC2086
    set -- $zeile
    pfad="$1"; soll="${2:-200}"; budget="${3:-3}"; shift 3 2>/dev/null || shift $#
    inhalt="$*"
    n=$((n + 1))
    if [ "$trocken" -eq 1 ]; then
        printf '%-28s Status %s  ≤ %s s%s\n' "$pfad" "$soll" "$budget" "${inhalt:+  enthält: $inhalt}"
        continue
    fi
    start="$EPOCHREALTIME"
    antwort="$(abruf "$pfad" "$budget")"
    dauer="$(awk -v a="$start" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.2f", b - a }')"
    status="${antwort%%$'\n'*}"
    body="${antwort#*$'\n'}"
    if [ "$status" != "$soll" ]; then
        printf 'ROT    %-28s Status %s erwartet, %s bekommen (%s s)\n' "$pfad" "$soll" "$status" "$dauer"; rot=$((rot + 1))
    elif [ -n "$inhalt" ] && ! printf '%s' "$body" | grep -qF -- "$inhalt"; then
        printf 'ROT    %-28s Pflichtinhalt „%s“ fehlt in der Antwort (Status %s, %s s)\n' "$pfad" "$inhalt" "$status" "$dauer"; rot=$((rot + 1))
    elif awk -v d="$dauer" -v b="$budget" 'BEGIN { exit !(d > b) }'; then
        printf 'ROT    %-28s %s s über dem Budget von %s s (Status %s)\n' "$pfad" "$dauer" "$budget" "$status"; rot=$((rot + 1))
    else
        printf 'ok     %-28s Status %s, %s s\n' "$pfad" "$status" "$dauer"
    fi
done < "$liste"

[ "$n" -gt 0 ] || { printf 'FEHLER: %s nennt keine Route — ein Rauchtest ohne Routen ist kein Tor.\n' "$liste" >&2; exit 2; }
[ "$trocken" -eq 1 ] && exit 0
if [ "$rot" -ne 0 ]; then
    printf 'Rauchtest: %s von %s Routen rot — deploy/smoke.txt nennt Status, Budget und Pflichtinhalt.\n' "$rot" "$n" >&2
    exit 1
fi
printf 'Rauchtest: alle %s Routen grün.\n' "$n"
