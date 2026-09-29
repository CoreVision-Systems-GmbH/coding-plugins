#!/usr/bin/env bash
# container-test.sh — Probelauf des gehärteten Verbunds: baut das Abbild aus dem Arbeitsstand
# und startet es so gehärtet wie auf dem Server (read_only, cap_drop: ALL, no-new-privileges,
# tmpfs) — einmal wie Prod (compose.yaml), einmal wie die Dev-Instanz (dazu compose.dev.yaml).
#
# Aufruf:   deploy/container-test.sh [prod|dev]       ohne Angabe: beide
#           in der CI (tests.yml, Schritt „Gehärteter Verbund startet“) — lokal nur in einem
#           Klon ohne .env
# Prüft:    alle Dienste gesund (Healthchecks; ohne Zustandstest: läuft), keiner neu gestartet
#           oder abgebrochen, und jeder Container aus dem eigenen Abbild kann in seine Volumes
#           und tmpfs schreiben.
# Ändert:   legt für den Lauf eine .env aus .env.example mit Wegwerf-Werten an und löscht sie
#           danach; startet den Verbund als Projekt <name>-probe und räumt ihn samt Volumes ab;
#           legt das Netz `edge` an, wenn es fehlt, und entfernt es danach wieder. Das gebaute
#           Abbild <name>:local bleibt liegen (es ersetzt ein gleichnamiges).
# NICHT:    auf einem Server (/etc/corevision/server.env) — die festen Container-Namen träfen
#           die echte Instanz; eine vorhandene .env wird nie angefasst.
# Rückweg:  docker compose -p <name>-probe down -v; rm .env
#
# Warum: Bis 1.5.0 wurde die Härtung nur gelesen, nie gestartet. Im Pilot scheiterte der erste
# Start auf dem Dev-Server an vier Fehlern, die kein Test sah — leeres tmpfs, File-Capability
# gegen cap_drop: ALL, schreibende DevTools, root ohne Schreibrecht (Issue #85, 2026-09-29).

set -euo pipefail
cd "$(dirname "$0")/.."

NAME="{{NAME}}"
projekt="$NAME-probe"

abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

case "${1:-beide}" in
    prod)       varianten="prod" ;;
    dev)        varianten="dev" ;;
    beide)      varianten="prod dev" ;;
    -h|--help)  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          abbruch "Unbekannte Variante: $1 (prod, dev oder ohne Angabe für beide)." ;;
esac

[ ! -f /etc/corevision/server.env ] \
    || abbruch "Nicht auf einem Server — die Dev-Instanz startet deploy/dev.sh up."
[ ! -e .env ] \
    || abbruch ".env ist vorhanden — der Probelauf braucht einen Klon ohne .env (etwa die CI) und überschreibt keine."
[ -f .env.example ] || abbruch ".env.example fehlt."
command -v docker >/dev/null 2>&1 || abbruch "docker fehlt."

# Wegwerf-Werte für jeden leeren Schlüssel: Geheimnisse zufällig, Konten mit Platzhaltern.
# Laravel verlangt für APP_KEY das Format base64:<32 Byte>.
zufall() { od -An -N24 -tx1 /dev/urandom | tr -d ' \n'; }
env_anlegen() {
    local zeile
    while IFS= read -r zeile || [ -n "$zeile" ]; do
        case "$zeile" in
            APP_VERSION=*)  echo "APP_VERSION=local" ;;
            APP_KEY=)       echo "APP_KEY=base64:$(head -c 32 /dev/urandom | base64 | tr -d '\n')" ;;
            *_EMAIL=)       echo "${zeile}probe@example.invalid" ;;
            *_USER=)        echo "${zeile}probe" ;;
            [A-Z]*=)        echo "${zeile}$(zufall)" ;;
            *)              printf '%s\n' "$zeile" ;;
        esac
    done < .env.example > .env
}

compose() { # <variante> <argumente …>
    local variante="$1"; shift
    local dateien=(-f compose.yaml -f compose.build.yaml)
    [ "$variante" = dev ] && dateien+=(-f compose.dev.yaml)
    APP_VERSION=local DEV_BIND_IP=127.0.0.1 docker compose -p "$projekt" "${dateien[@]}" "$@"
}

netz_angelegt=0
aufraeumen() {
    compose dev down -v --remove-orphans >/dev/null 2>&1 || true
    compose prod down -v --remove-orphans >/dev/null 2>&1 || true
    [ "$netz_angelegt" -eq 0 ] || docker network rm edge >/dev/null 2>&1 || true
    rm -f .env
}

# Warten, bis jeder Dienst gesund ist. Ein Dienst ohne Zustandstest (Worker, Cron) zählt, sobald
# er läuft und — aus dem eigenen Abbild — sein Einstiegspunkt durch ist: Solange PID 1 noch
# `entrypoint` heißt, wartet er etwa noch auf die Datenbank und könnte danach abbrechen. Ein
# erledigter Einmal-Auftrag (exited 0) zählt ebenso. Eigene Schleife statt `up --wait`: Compose
# 2.38.2 auf den GitHub-Runnern bricht dort bei `healthcheck: disable: true` mit „has no
# healthcheck configured“ ab, obwohl der Dienst läuft (belegt 2026-09-29; v5.5.1 nicht).
einstieg_laeuft() { # <container-id> — eigenes Abbild und PID 1 noch der Einstiegspunkt?
    [ "$(docker inspect -f '{{.Config.Image}}' "$1")" = "$NAME:local" ] \
        && docker exec "$1" cat /proc/1/cmdline 2>/dev/null | tr '\0' ' ' | grep -q entrypoint
}
warten() { # <variante>
    local ende=$((SECONDS + 300)) id zustand offen ids=()
    while :; do
        offen=0
        mapfile -t ids < <(compose "$1" ps -aq)
        [ "${#ids[@]}" -gt 0 ] || offen=1
        for id in "${ids[@]}"; do
            zustand="$(docker inspect -f '{{.State.Status}} {{.State.ExitCode}} {{if .State.Health}}{{.State.Health.Status}}{{else}}ohne{{end}}' "$id")"
            case "$zustand" in
                # Neustarts meldet stabil() danach, hier zählt nur der Zustand.
                "running "*" healthy"|"exited 0 ohne") ;;
                "running "*" ohne") ! einstieg_laeuft "$id" || offen=1 ;;
                # Neustartschleife sofort melden, nicht erst nach der Frist (Gegenprobe #87:
                # „exec /usr/bin/caddy: operation not permitted“, Restarting (255)).
                exited*|dead*|restarting*) printf 'Abgebrochen: %s (%s)\n' "$(docker inspect -f '{{.Name}}' "$id")" "$zustand" >&2; return 1 ;;
                *) offen=1 ;;
            esac
        done
        [ "$offen" -eq 1 ] || return 0
        if [ "$SECONDS" -ge "$ende" ]; then
            printf 'Nach 300 s nicht alle Dienste gesund.\n' >&2
            return 1
        fi
        sleep 3
    done
}

diagnose() { # <variante>
    printf -- '-- Zustand\n' >&2
    compose "$1" ps -a >&2 || true
    printf -- '-- Protokolle (je Dienst die letzten 40 Zeilen)\n' >&2
    compose "$1" logs --no-color --tail 40 >&2 || true
}

# Kein Dienst darf neu gestartet oder abgebrochen sein; ein erledigter Einmal-Auftrag
# (exited 0) ist in Ordnung.
stabil() { # <variante>
    local id zustand gut=0 ids=()
    mapfile -t ids < <(compose "$1" ps -aq)
    for id in "${ids[@]}"; do
        zustand="$(docker inspect -f '{{.Name}} {{.State.Status}} {{.State.ExitCode}} {{.RestartCount}}' "$id")"
        case "$zustand" in
            *" running 0 0"|*" exited 0 0") ;;
            *) printf 'Nicht stabil (Name Zustand Ausgang Neustarts): %s\n' "$zustand" >&2; gut=1 ;;
        esac
    done
    return "$gut"
}

# Jeder Container aus dem eigenen Abbild schreibt als sein Laufzeitnutzer in jedes Volume und
# jedes tmpfs — genau das scheiterte im Pilot (root ohne CAP_DAC_OVERRIDE, tmpfs von root).
schreibbar() {
    local id pfad gut=0 ids=() pfade=()
    mapfile -t ids < <(docker ps -q --filter "label=com.docker.compose.project=$projekt" --filter "ancestor=$NAME:local")
    # Ohne Treffer prüfte die Schleife nichts und wäre still grün.
    [ "${#ids[@]}" -gt 0 ] || { printf 'Kein laufender Container aus dem Abbild %s:local gefunden.\n' "$NAME" >&2; return 1; }
    for id in "${ids[@]}"; do
        mapfile -t pfade < <(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Destination}}{{end}}{{end}}{{range $p, $o := .HostConfig.Tmpfs}}{{println $p}}{{end}}' "$id" | sed '/^$/d')
        for pfad in "${pfade[@]}"; do
            if docker exec "$id" sh -c 'f="$1/.probelauf-$$" && : > "$f" && rm -f "$f"' sh "$pfad" >/dev/null 2>&1; then
                printf '   schreibbar: %s %s\n' "$(docker inspect -f '{{.Name}}' "$id")" "$pfad"
            else
                printf 'Nicht schreibbar: %s %s\n' "$(docker inspect -f '{{.Name}}' "$id")" "$pfad" >&2
                gut=1
            fi
        done
    done
    return "$gut"
}

env_anlegen
trap aufraeumen EXIT
if ! docker network inspect edge >/dev/null 2>&1; then
    docker network create edge >/dev/null
    netz_angelegt=1
fi

printf '== docker compose %s\n' "$(docker compose version --short 2>/dev/null || echo '(Fassung unbekannt)')"
rot=0
for variante in $varianten; do
    printf '== Probelauf %s: bauen und gehärtet starten\n' "$variante"
    if ! compose "$variante" up -d --build || ! warten "$variante"; then
        printf 'ROT: Der Verbund (%s) wurde nicht gesund.\n' "$variante" >&2
        diagnose "$variante"; rot=1
    elif ! stabil "$variante" || ! schreibbar; then
        printf 'ROT: Der Verbund (%s) läuft, aber nicht wie verlangt.\n' "$variante" >&2
        diagnose "$variante"; rot=1
    else
        printf '== Probelauf %s: grün\n' "$variante"
    fi
    compose "$variante" down -v --remove-orphans >/dev/null 2>&1 || true
done

exit "$rot"
