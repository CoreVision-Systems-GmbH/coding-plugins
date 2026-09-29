#!/usr/bin/env bash
# test-server.sh — prüft setup-server.sh, geoblock, edge-site und rollout, ohne einen Server
# anzufassen.
#
# Aufruf:   bash plugins/coding-standard/server/test-server.sh
# Ergebnis: Exit 0, wenn alle Fälle grün sind, sonst Exit 1.
#
# Die Skripte laufen gegen ein Wegwerf-Dateisystem (SERVER_WURZEL) und Attrappen für apt-get,
# dpkg, docker, ufw, nft, tailscale, systemctl, sysctl, ip, id und curl. Die Attrappen
# protokollieren ihre Aufrufe und merken sich Zustand (installierte Pakete, ufw-Regeln, geladene
# nft-Regeln, laufender Edge). Geprüft werden: Rollen (ufw, Bindung, dev.-Präfix), Geoblocking
# (Länderauswahl, Ausnahmen, Ablehnung unplausibler Listen, fail-closed), DNS-Wahl (Caddyfile,
# API-Aufrufe, acme-dns-CNAME), Idempotenz, Trockenlauf ohne Änderung, Aussperrschutz für SSH und
# Geoblocking, Fehlerausgänge. Ob die Sperre im Kernel wirkt, prüft test-geoblock-netz.sh.
# Die edge-site-Fälle mit DNS-API und `dienst:googlebot` brauchen jq (auf dem Server installiert es
# setup-server.sh); ohne jq werden sie übersprungen — die CI führt sie auf Ubuntu aus.

# Prüfmuster `[ … ]; behaupte "…" $?`: $? soll das Ergebnis der Bedingung sein (SC2319).
# shellcheck disable=SC2319

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$HERE/setup-server.sh"
SITE="$HERE/edge-site"
BASH_BIN="$BASH"

fehler=0
behaupte() { if [ "$2" -eq 0 ]; then echo "ok     $1"; else echo "FEHLER $1"; fehler=$((fehler + 1)); fi; }

tmp="$(mktemp -d)"
trap '[ -n "${BEHALTEN:-}" ] || rm -rf "$tmp"' EXIT

# --- Werkzeugkasten: Grundbefehle als Weiterleitung, dazu jq, falls vorhanden
mkdir -p "$tmp/bin"
for w in grep sed head tail tr cat mkdir chmod cp rm mv touch stat mktemp dirname env wc find awk readlink ln install sort cut basename printf gzip date jq; do
    p="$(command -v "$w" 2>/dev/null)" || continue
    case "$p" in /*) ;; *) continue ;; esac
    printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$p" > "$tmp/bin/$w"; chmod +x "$tmp/bin/$w"
done
hat_jq=0; [ -x "$tmp/bin/jq" ] && hat_jq=1

stub() { mkdir -p "$1"; printf '#!%s\n%s\n' "$BASH_BIN" "$3" > "$1/$2"; chmod +x "$1/$2"; }

# Attrappen: Zustand liegt in $ZUSTAND, Aufrufe in $ZUSTAND/log
S="$tmp/stubs"
stub "$S" apt-get 'echo "apt-get $*" >> "$ZUSTAND/log"; case "$1" in install) shift; for p in "$@"; do case "$p" in -*) ;; *) echo "$p" >> "$ZUSTAND/pakete";; esac; done;; esac'
stub "$S" dpkg 'case "$1" in -s) grep -qx "$2" "$ZUSTAND/pakete" 2>/dev/null;; --print-architecture) echo amd64;; esac'
stub "$S" systemctl 'echo "systemctl $*" >> "$ZUSTAND/log"
case "$1" in
  is-enabled) [ -f "$ZUSTAND/an-${!#}" ];;
  is-failed) [ -f "$ZUSTAND/gescheitert-${!#}" ];;
  enable) for a in "$@"; do case "$a" in enable|--now) ;; *) touch "$ZUSTAND/an-$a";; esac; done;;
esac'
# nft: -c prüft, -f lädt (Kopie nach nft-geladen), nft-ungueltig lässt beides scheitern;
# get element findet jede Adresse außer denen in nft-fremd (Aussperrschutz).
stub "$S" nft 'echo "nft $*" >> "$ZUSTAND/log"
case "$1" in
  -c) [ ! -f "$ZUSTAND/nft-ungueltig" ];;
  -f) [ ! -f "$ZUSTAND/nft-ungueltig" ] && cp "$2" "$ZUSTAND/nft-geladen";;
  list) [ -f "$ZUSTAND/nft-geladen" ] && cat "$ZUSTAND/nft-geladen";;
  delete) rm -f "$ZUSTAND/nft-geladen";;
  get) for f in $(cat "$ZUSTAND/nft-fremd" 2>/dev/null); do [ "$6" = "{ $f }" ] && exit 1; done; true;;
esac'
stub "$S" sysctl 'echo "sysctl $*" >> "$ZUSTAND/log"'
stub "$S" id 'echo 0'
stub "$S" who '[ -f "$ZUSTAND/who" ] && cat "$ZUSTAND/who"; true'   # who -m: Gegenstelle, wenn sudo SSH_CONNECTION entfernt
stub "$S" logger 'shift 2; [ "$1" = -- ] && shift; echo "$*" >> "$ZUSTAND/journal"'   # logger -t geoblock -- <text>
stub "$S" ip 'echo "1.1.1.1 via 203.0.113.1 dev eth0 src 203.0.113.10 uid 0"'
stub "$S" tailscale 'case "$*" in "ip -4") [ -n "${TS_IP:-}" ] && echo "$TS_IP";; esac'
stub "$S" ufw 'echo "ufw $*" >> "$ZUSTAND/log"
case "$1" in
  status) if [ -f "$ZUSTAND/ufw-an" ]; then echo "Status: active"; else echo "Status: inactive"; fi; cat "$ZUSTAND/ufw-regeln" 2>/dev/null;;
  --force) [ "$2" = enable ] && touch "$ZUSTAND/ufw-an"; [ "$2" = delete ] && { shift 3; grep -v "^$* " "$ZUSTAND/ufw-regeln" > "$ZUSTAND/r" 2>/dev/null; mv "$ZUSTAND/r" "$ZUSTAND/ufw-regeln"; };;
  allow) [ "$2" = 22/tcp ] && { grep -q "^22/tcp " "$ZUSTAND/ufw-regeln" 2>/dev/null || echo "22/tcp                     ALLOW       Anywhere" >> "$ZUSTAND/ufw-regeln"; };;
esac
exit 0'
stub "$S" docker 'echo "docker $*" >> "$ZUSTAND/log"
case "$*" in
  "--version") echo "Docker version 29.0.0";;
  "compose version"*) echo "2.40.0";;
  "network inspect edge") [ -f "$ZUSTAND/netz" ];;
  "network create edge") touch "$ZUSTAND/netz";;
  *" ps --status running -q caddy") [ -f "$ZUSTAND/edge-laeuft" ] && echo abc123;;
  *" up -d --build") touch "$ZUSTAND/edge-laeuft";;
  *" exec -T caddy caddy validate"*) [ ! -f "$ZUSTAND/validate-fehler" ];;
  *) ;;
esac'
# curl: Downloads legen leere Dateien an; API-Aufrufe antworten mit festen JSON-Texten.
stub "$S" curl 'echo "curl $*" >> "$ZUSTAND/log"
# Wie das echte curl: Mit -H @- kommt der Authorization-Header über stdin.
case " $* " in *" @- "*) cat > /dev/null;; esac
# Kopfabfrage (edge-site check): HSTS nur, wenn der Zustand es vorgibt.
case " $* " in *" -sI "*) [ -f "$ZUSTAND/hsts" ] && printf "HTTP/2 200\r\nstrict-transport-security: max-age=31536000\r\n\r\n"; exit 0;; esac
out=""; url=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; case "$a" in http*) url="$a";; esac; prev="$a"; done
# Länderliste (Probe in zustand/dbip.csv.gz, dbip-fehlt-<monat> heißt 404) und Dienstlisten
case "$url" in
  *download.db-ip.com/*) m="${url##*lite-}"; m="${m%.csv.gz}"
      { [ ! -f "$ZUSTAND/dbip-fehlt-$m" ] && [ -f "$ZUSTAND/dbip.csv.gz" ]; } || exit 22
      cp "$ZUSTAND/dbip.csv.gz" "$out"; exit 0;;
  *googlebot.json) printf "{\"prefixes\":[{\"ipv6Prefix\":\"2001:4860:4801:10::/64\"},{\"ipv4Prefix\":\"66.249.64.0/27\"}]}" > "$out"; exit 0;;
  *ips_webhooks.txt) [ -f "$ZUSTAND/dienst-fehlt" ] && exit 22; printf "3.18.12.63\r\n3.130.192.231\r\n" > "$out"; exit 0;;
  *IPv4andIPv6.txt) printf "0.0.0.0/0\n::/0\n1.2.3.0/8\n5.6.7.8\n" > "$out"; exit 0;;   # zu weite Einträge einer fremden Liste
esac
if [ -n "$out" ]; then : > "$out"; exit 0; fi
case "$url" in
  *hetzner.cloud/v1/zones\?name=example.at) echo "{\"zones\":[{\"name\":\"example.at\"}]}";;
  *hetzner.cloud/v1/zones\?name=*) echo "{\"zones\":[]}";;
  *hetzner.cloud/v1/zones/example.at/rrsets/*/A) [ -f "$ZUSTAND/rrset-da" ] || exit 22; echo "{}";;
  *hetzner.cloud/v1/zones/example.at/rrsets) touch "$ZUSTAND/rrset-da"; echo "{}";;
  *cloudflare.com/client/v4/zones\?name=example.at) echo "{\"result\":[{\"id\":\"z1\"}]}";;
  *cloudflare.com/client/v4/zones\?name=*) echo "{\"result\":[]}";;
  *cloudflare.com/client/v4/zones/z1/dns_records\?*) echo "{\"result\":[]}";;
  *cloudflare.com*) echo "{\"success\":true}";;
  */register) echo "{\"username\":\"u1\",\"password\":\"p1\",\"subdomain\":\"s1\",\"fulldomain\":\"s1.auth.acme-dns.io\",\"allowfrom\":[]}";;
  *) echo "{}";;
esac'

# Probeliste im Format von db-ip: AT, DE, CH, LI (LI als Einzeladresse) aus 203.0.113.0/24,
# dazu US-Bereiche und je ein IPv6-Bereich für AT und US.
printf '%s\n' '0.0.0.0,0.255.255.255,ZZ' '66.249.64.0,66.249.95.255,US' '198.51.100.0,198.51.100.255,US' \
    '203.0.113.0,203.0.113.127,AT' '203.0.113.128,203.0.113.191,DE' '203.0.113.192,203.0.113.223,CH' \
    '203.0.113.224,203.0.113.224,LI' '2001:db8:a::,2001:db8:a:ffff:ffff:ffff:ffff:ffff,AT' \
    '2001:db8:f::,2001:db8:f:ffff:ffff:ffff:ffff:ffff,US' '2003:4000::,23ff:ffff:ffff:ffff:ffff:ffff:ffff:ffff,CH' \
    | gzip > "$tmp/dbip.csv.gz"

neue_welt() { # neue_welt <name> — frisches Dateisystem mit Ubuntu 26.04
    local w="$tmp/$1"
    mkdir -p "$w/etc/apt/sources.list.d" "$w/zustand"
    printf 'ID=ubuntu\nVERSION_ID="26.04"\nVERSION_CODENAME=resolute\n' > "$w/etc/os-release"
    cp "$tmp/dbip.csv.gz" "$w/zustand/dbip.csv.gz"
    printf '%s' "$w"
}
# set_von <nft-datei> <set> — der Block eines Sets, von „set <name> {“ bis zu seiner schließenden Klammer
set_von() { awk -v s="set $2 {" 'index($0, s) { an = 1 } an { print } an && /^\t}$/ { exit }' "$1"; }
lauf() { # lauf <welt> <skript> <argumente…> — isoliert, mit Attrappen
    local w="$1" skript="$2"; shift 2
    env -i PATH="$tmp/bin:$S" HOME="$w/root" SERVER_WURZEL="$w" ZUSTAND="$w/zustand" \
        TS_IP="${TS_IP:-}" SSH_CONNECTION="${SSH_CONNECTION:-}" DNS_API_TOKEN="${DNS_API_TOKEN:-}" \
        "$BASH_BIN" "$skript" "$@" 2>&1
}

# --- Grundlagen und Fehlerausgänge
bash -n "$SETUP"; behaupte "setup-server.sh: Syntax" $?
bash -n "$SITE"; behaupte "edge-site: Syntax" $?
w="$(neue_welt args)"
lauf "$w" "$SETUP" --help | grep -q -- "--rolle dev|prod"; behaupte "setup-server.sh: --help" $?
lauf "$w" "$SETUP" --dns hetzner --email a@b.at >/dev/null; [ $? -eq 1 ]; behaupte "setup-server.sh: ohne --rolle endet mit 1" $?
lauf "$w" "$SETUP" --rolle test --dns hetzner --email a@b.at >/dev/null; [ $? -eq 1 ]; behaupte "setup-server.sh: unbekannte Rolle endet mit 1" $?
lauf "$w" "$SETUP" --rolle dev --dns route53 --email a@b.at >/dev/null; [ $? -eq 1 ]; behaupte "setup-server.sh: unbekannter DNS-Weg endet mit 1" $?
lauf "$w" "$SETUP" --rolle dev --dns hetzner --email keine-adresse >/dev/null; [ $? -eq 1 ]; behaupte "setup-server.sh: ungültige E-Mail endet mit 1" $?
printf 'ID=ubuntu\nVERSION_ID="22.04"\nVERSION_CODENAME=jammy\n' > "$w/etc/os-release"
lauf "$w" "$SETUP" --rolle dev --dns hetzner --email a@b.at | grep -q "keine unterstützte LTS"; behaupte "setup-server.sh: Ubuntu 22.04 wird abgelehnt" $?
printf 'ID=debian\nVERSION_ID="13"\n' > "$w/etc/os-release"
lauf "$w" "$SETUP" --rolle dev --dns hetzner --email a@b.at | grep -q "Nur für Ubuntu"; behaupte "setup-server.sh: Debian wird abgelehnt" $?

# --- Trockenlauf ändert nichts
w="$(neue_welt trocken)"
out="$(TS_IP=100.64.0.5 lauf "$w" "$SETUP" --rolle dev --dns hetzner --email a@b.at --dry-run)"; rc=$?
[ $rc -eq 0 ] && printf '%s' "$out" | grep -q "Trockenlauf beendet"; behaupte "setup-server.sh: --dry-run endet mit 0" $?
[ ! -e "$w/opt" ] && [ ! -e "$w/etc/corevision" ] && [ ! -s "$w/zustand/pakete" ]; behaupte "setup-server.sh: --dry-run schreibt und installiert nichts" $?
[ ! -e "$w/var/lib" ] && [ ! -e "$w/etc/systemd" ] && ! grep -qE "nft -f|download.db-ip" "$w/zustand/log"; behaupte "setup-server.sh: --dry-run lädt keine Länderliste und kein Geoblocking" $?

# --- Dev mit Hetzner: Pakete, Bindung, Caddyfile, ufw, Befehle
w="$(neue_welt dev)"
out="$(TS_IP=100.64.0.5 SSH_CONNECTION="100.64.0.9 5000 100.64.0.5 22" DNS_API_TOKEN=geheim lauf "$w" "$SETUP" --rolle dev --dns hetzner --email admin@example.at)"; rc=$?
[ $rc -eq 0 ]; behaupte "Dev/Hetzner: Einrichtung endet mit 0" $?
[ $rc -eq 0 ] || printf '%s\n' "$out" | grep -E "FEHL|HAND" | sed 's/^/       /'
grep -qx docker-compose-plugin "$w/zustand/pakete" && grep -qx tailscale "$w/zustand/pakete"; behaupte "Dev: Docker Compose und Tailscale installiert" $?
grep -q "^Suites: resolute" "$w/etc/apt/sources.list.d/docker.sources"; behaupte "Dev: Docker-Repo im deb822-Format für resolute" $?
grep -q "^BIND_IP=100.64.0.5$" "$w/opt/edge/.env"; behaupte "Dev: Edge bindet nur an die Tailscale-IP" $?
grep -q "^ZIEL_IP=100.64.0.5$" "$w/etc/corevision/server.env"; behaupte "Dev: A-Records zeigen auf die Tailscale-IP" $?
{ case "$(uname -s)" in MINGW*|MSYS*) true ;; *) [ "$(stat -c %a "$w/opt/edge/.env")" = 600 ] ;; esac; } && grep -q "^DNS_API_TOKEN=geheim$" "$w/opt/edge/.env"; behaupte "Dev: Token nur in /opt/edge/.env (600)" $?
grep -q "dns hetzner {env.DNS_API_TOKEN}" "$w/opt/edge/caddy/Caddyfile" && grep -q "import sites/\*.caddy" "$w/opt/edge/caddy/Caddyfile"; behaupte "Dev: Caddyfile mit Hetzner-DNS-01 und sites/" $?
grep -q "ufw allow 80/tcp" "$w/zustand/log"; [ $? -ne 0 ]; behaupte "Dev: keine öffentlichen Ports 80/443" $?
grep -q "ufw allow in on tailscale0" "$w/zustand/log" && grep -q "ufw --force enable" "$w/zustand/log"; behaupte "Dev: ufw an, Tailnet erlaubt" $?
grep -q "ufw allow 22/tcp" "$w/zustand/log"; [ $? -ne 0 ]; behaupte "Dev: SSH über Tailnet — kein öffentliches 22" $?
[ -x "$w/usr/local/bin/edge-site" ] && grep -q "exec bash .*/edge-site" "$w/usr/local/bin/edge-site"; behaupte "Dev: Befehl edge-site installiert" $?
grep -q "docker compose -f $w/opt/edge/compose.yaml up -d --build" "$w/zustand/log"; behaupte "Dev: Edge gebaut und gestartet" $?
grep -q "download.docker.com/linux/ubuntu/gpg" "$w/zustand/log" && ! grep -q "get.docker.com" "$w/zustand/log"; behaupte "Dev: Docker aus dem signierten Repo, nicht get.docker.com" $?

# Geoblocking (ADR 0008): auf Dev und Prod, vor dem Edge
gb_regeln="$w/var/lib/corevision/geoblock/regeln.nft"
grep -qx nftables "$w/zustand/pakete" && grep -q "^LAENDER=AT,CH,LI,DE$" "$w/etc/corevision/geoblock.conf"; behaupte "Dev: nftables installiert, Geoblocking mit Vorgabe AT, CH, LI, DE" $?
[ -s "$gb_regeln" ] && cmp -s "$gb_regeln" "$w/zustand/nft-geladen" && grep -q "nft -c -f" "$w/zustand/log"; behaupte "Geoblocking: Regeln mit nft -c geprüft, geladen und gespeichert" $?
set_von "$gb_regeln" erlaubt4 | grep -q "203.0.113.0-203.0.113.127," && set_von "$gb_regeln" erlaubt4 | grep -q "203.0.113.192-203.0.113.223," \
    && set_von "$gb_regeln" erlaubt4 | grep -qE "[[:space:]]203\.0\.113\.224$"; behaupte "Geoblocking: IPv4 der vier Länder, Einzeladresse ohne Bereich" $?
set_von "$gb_regeln" erlaubt6 | grep -q "2001:db8:a::-2001:db8:a:ffff" && ! set_von "$gb_regeln" erlaubt4 | grep -q ":"; behaupte "Geoblocking: IPv6 im eigenen Set" $?
! grep -qE "198\.51\.100|66\.249|2001:db8:f::" "$gb_regeln"; behaupte "Geoblocking: Bereiche anderer Länder fehlen" $?
grep -q "hook prerouting priority -150;" "$gb_regeln" && grep -q 'iifname { "lo", "tailscale0" } accept' "$gb_regeln" \
    && grep -q "ct state established,related accept" "$gb_regeln" && tail -3 "$gb_regeln" | grep -q "counter drop"; behaupte "Geoblocking: am Hook prerouting (auch weitergeleitete Docker-Pakete), Tailnet und Antworten frei, sonst verworfen" $?
[ -x "$w/usr/local/bin/geoblock" ] && cmp -s "$w/usr/local/bin/geoblock" "$HERE/geoblock"; behaupte "Geoblocking: Befehl als Kopie installiert — beim Start läuft kein Code aus dem Klon" $?
[ -f "$w/zustand/an-corevision-geoblock.service" ] && [ -f "$w/zustand/an-corevision-geoblock-aktualisieren.timer" ] \
    && [ -f "$w/zustand/an-corevision-geoblock-waechter.timer" ]; behaupte "Geoblocking: Dienst, Aktualisierung und Wächter eingeschaltet" $?
! grep -q "2003:4000" "$gb_regeln"; behaupte "Geoblocking: IPv6-Bereich über den ersten Block hinaus (Lückenfüller) verworfen" $?
grep -q "^Before=network-pre.target docker.service tailscaled.service$" "$w/etc/systemd/system/corevision-geoblock.service" \
    && grep -q "^OnCalendar=Mon \*-\*-\* 04:30:00 Europe/Vienna$" "$w/etc/systemd/system/corevision-geoblock-aktualisieren.timer"; behaupte "Geoblocking: lädt vor Netz und Docker, Liste jeden Montag (Europe/Vienna)" $?
# Der Startbefehl der Einheit, so wie systemd ihn ausführt (Pfade in die Testwelt umgelegt)
start="$(sed -n "s/^ExecStart=\/bin\/sh -c '\(.*\)'$/\1/p" "$w/etc/systemd/system/corevision-geoblock.service")"
start="${start//\/var\/lib\//$w/var/lib/}"
start_lauf() { env -i PATH="$tmp/bin:$S" ZUSTAND="$w/zustand" "$BASH_BIN" -c "$start" >/dev/null 2>&1; }
rm -f "$w/zustand/nft-geladen"; start_lauf && cmp -s "$gb_regeln" "$w/zustand/nft-geladen"; behaupte "Start: lädt die gespeicherte Sperre nur mit nft, ohne Skript" $?
mv "$gb_regeln" "$tmp/regeln-gut"; start_lauf; rc=$?
[ $rc -ne 0 ] && cmp -s "$w/var/lib/corevision/geoblock/gesperrt.nft" "$w/zustand/nft-geladen" && ! grep -q "elements" "$w/zustand/nft-geladen"; behaupte "Start: gespeicherte Sperre fehlt → gesperrte Fassung, Exit ≠ 0" $?
mv "$tmp/regeln-gut" "$gb_regeln"; cp "$gb_regeln" "$w/zustand/nft-geladen"

# Idempotenz: zweiter Lauf ohne Änderung
: > "$w/zustand/log"
out2="$(TS_IP=100.64.0.5 SSH_CONNECTION="100.64.0.9 5000 100.64.0.5 22" lauf "$w" "$SETUP")"; rc=$?
[ $rc -eq 0 ]; behaupte "Dev: zweiter Lauf (gespeicherte Werte) endet mit 0" $?
printf '%s' "$out2" | grep -q "   mache "; [ $? -ne 0 ]; behaupte "Dev: zweiter Lauf ändert nichts" $?
[ $? -eq 0 ] || printf '%s\n' "$out2" | grep "mache" | sed 's/^/       /'
grep -qE "apt-get install|up -d --build" "$w/zustand/log"; [ $? -ne 0 ]; behaupte "Dev: zweiter Lauf installiert und baut nicht" $?
out3="$(TS_IP=100.64.0.5 lauf "$w" "$SETUP" --check)"; rc=$?
[ $rc -eq 0 ] && printf '%s' "$out3" | grep -q "erfüllt den Standard"; behaupte "Dev: --check endet mit 0" $?
printf '%s' "$out3" | grep -q "ok      Geoblocking aktiv: 4 IPv4- und 1 IPv6-Bereiche, 0 Ausnahmen"; behaupte "Dev: --check belegt das Geoblocking" $?
rm "$w/zustand/nft-geladen"
out3="$(TS_IP=100.64.0.5 lauf "$w" "$SETUP" --check)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out3" | grep -q "FEHLT   Geoblocking aktiv"; behaupte "Dev: --check rot ohne geladene Sperre" $?
lauf "$w" "$HERE/geoblock" laden >/dev/null; cmp -s "$gb_regeln" "$w/zustand/nft-geladen"; behaupte "geoblock laden: lädt beim Start die gespeicherten Regeln" $?

# --- Dev ohne Tailscale: Handgriff statt Start, SSH bleibt offen
w="$(neue_welt dev-ohne-ts)"
out="$(TS_IP='' SSH_CONNECTION="198.51.100.7 5000 203.0.113.10 22" DNS_API_TOKEN=geheim lauf "$w" "$SETUP" --rolle dev --dns hetzner --email admin@example.at)"; rc=$?
[ $rc -eq 0 ] && printf '%s' "$out" | grep -q "HAND    Tailscale anmelden"; behaupte "Dev ohne Tailscale: Einrichtung endet mit 0, Handgriff tailscale up" $?
[ "$(printf '%s' "$out" | grep -c "HAND .*tailscale up")" -eq 1 ]; behaupte "Dev ohne Tailscale: der Handgriff steht genau einmal da" $?
grep -q "ufw allow 22/tcp" "$w/zustand/log"; behaupte "Dev ohne Tailscale: SSH bleibt offen (kein Aussperren)" $?
grep -q "up -d --build" "$w/zustand/log"; [ $? -ne 0 ]; behaupte "Dev ohne Tailscale: Edge startet nicht ohne Tailscale-IP" $?
out="$(TS_IP='' lauf "$w" "$SETUP" --check)"; rc=$?
[ $rc -ne 0 ]; behaupte "Dev ohne Tailscale: --check endet ≠ 0" $?

# SSH-Wechsel ins Tailnet schließt 22 wieder
: > "$w/zustand/log"
TS_IP=100.64.0.5 SSH_CONNECTION="100.64.0.9 5000 100.64.0.5 22" lauf "$w" "$SETUP" >/dev/null
grep -q "ufw --force delete allow 22/tcp" "$w/zustand/log"; behaupte "Dev: über das Tailnet verbunden → öffentliches SSH wird geschlossen" $?

# sudo entfernt SSH_CONNECTION: unbekannte Gegenstelle → Port 22 bleibt offen (kein Aussperren)
w="$(neue_welt sudo-ohne-ssh)"
TS_IP='' DNS_API_TOKEN=geheim lauf "$w" "$SETUP" --rolle dev --dns hetzner --email admin@example.at >/dev/null
: > "$w/zustand/log"
out="$(TS_IP=100.64.0.5 SSH_CONNECTION='' lauf "$w" "$SETUP")"
grep -q "ufw --force delete allow 22/tcp" "$w/zustand/log"; [ $? -ne 0 ]; behaupte "SSH: Gegenstelle unbekannt (sudo) → 22 bleibt offen" $?
printf '%s' "$out" | grep -q "HAND    SSH ist noch öffentlich offen"; behaupte "SSH: Handgriff nennt den Weg über das Tailnet" $?
: > "$w/zustand/log"
TS_IP=100.64.0.5 SSH_CONNECTION="198.51.100.7 5000 203.0.113.10 22" lauf "$w" "$SETUP" >/dev/null
grep -q "ufw --force delete allow 22/tcp" "$w/zustand/log"; [ $? -ne 0 ]; behaupte "SSH: öffentliche Gegenstelle → 22 bleibt offen" $?
: > "$w/zustand/log"
TS_IP=100.64.0.5 SSH_CONNECTION="100.100.1.2 5000 100.64.0.5 22" lauf "$w" "$SETUP" >/dev/null
grep -q "ufw --force delete allow 22/tcp" "$w/zustand/log"; behaupte "SSH: Gegenstelle im Tailnet (100.64/10) → 22 schließt" $?
grep -q "^ZIEL_IP=100.64.0.5$" "$w/etc/corevision/server.env"; behaupte "Dev: Ziel-IP folgt der Tailscale-IP" $?
TS_IP=100.64.0.77 SSH_CONNECTION="100.100.1.2 5000 100.64.0.77 22" lauf "$w" "$SETUP" >/dev/null
grep -q "^ZIEL_IP=100.64.0.77$" "$w/etc/corevision/server.env" && grep -q "^BIND_IP=100.64.0.77$" "$w/opt/edge/.env"; behaupte "Dev: neue Tailscale-IP → Ziel und Bindung ziehen nach" $?
TS_IP='' SSH_CONNECTION="100.100.1.2 5000 100.64.0.77 22" lauf "$w" "$SETUP" >/dev/null
grep -q "^BIND_IP=100.64.0.77$" "$w/opt/edge/.env"; behaupte "Dev: Tailscale kurz weg → Bindung bleibt, wird nie leer oder 0.0.0.0" $?

# sudo entfernt SSH_CONNECTION ganz (nicht nur leer): kein Abbruch an set -u, who -m springt ein
w="$(neue_welt sudo-ohne-variable)"
TS_IP='' DNS_API_TOKEN=geheim lauf "$w" "$SETUP" --rolle dev --dns hetzner --email admin@example.at >/dev/null
: > "$w/zustand/log"; printf 'admin    pts/0        2026-09-29 12:00 (100.64.0.9)\n' > "$w/zustand/who"
out="$(env -i PATH="$tmp/bin:$S" HOME="$w/root" SERVER_WURZEL="$w" ZUSTAND="$w/zustand" TS_IP=100.64.0.5 "$BASH_BIN" "$SETUP" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ! printf '%s' "$out" | grep -q "unbound" && grep -q "ufw --force delete allow 22/tcp" "$w/zustand/log"
behaupte "SSH: ohne SSH_CONNECTION (sudo) läuft das Skript durch, who -m erkennt das Tailnet, 22 schließt" $?

# Rechte des Klons: Code, der als root läuft, darf niemand sonst schreiben (auch nicht die Elternordner)
# stat-Attrappe je Pfad: Pfade nach RECHTE_MUSTER bekommen RECHTE, alle anderen „root 755“.
S2="$tmp/stubs-rechte"; stub "$S2" stat 'case "$3" in ${RECHTE_MUSTER:-*}) echo "$RECHTE";; *) echo "root 755";; esac'
rechte_lauf() { env -i PATH="$S2:$tmp/bin:$S" HOME="$w/root" SERVER_WURZEL="$w" ZUSTAND="$w/zustand" SERVER_RECHTE_PRUEFEN=1 \
    RECHTE="$1" RECHTE_MUSTER="${2:-*}" TS_IP=100.64.0.5 SSH_CONNECTION="100.64.0.9 5000 100.64.0.5 22" "$BASH_BIN" "$SETUP" 2>&1; }
rechte_lauf "root 755" >/dev/null; behaupte "Rechte: root 755 überall → Einrichtung läuft" $?
for r in "root 722" "root 733" "root 775" "root 2775" "admin 755"; do
    out="$(rechte_lauf "$r")"; rc=$?
    [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "gehört nicht root oder ist für andere beschreibbar ($r)"
    behaupte "Rechte: $r → abgewiesen, bevor Code aus dem Klon als root läuft" $?
done
rechte_lauf "root 1755" >/dev/null; behaupte "Rechte: root 1755 (Sticky-Bit) → erlaubt" $?
# Nur ein Elternordner (…/plugins) ist beschreibbar: setup-server.sh und geoblock laufen den Weg bis / ab
out="$(rechte_lauf "root 777" "*/plugins")"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "/plugins gehört nicht root oder ist für andere beschreibbar (root 777)" \
    && printf '%s' "$out" | grep -q "/plugins gehört nicht root oder ist für andere beschreibbar — als root klonen bzw. Rechte korrigieren"
behaupte "Rechte: nur ein Elternordner beschreibbar → setup-server.sh und geoblock weisen ab" $?

# --- Prod mit Cloudflare: öffentliche Ports, alle Adressen
w="$(neue_welt prod)"
out="$(TS_IP=100.64.0.6 SSH_CONNECTION="100.64.0.9 5000 100.64.0.6 22" DNS_API_TOKEN=cf lauf "$w" "$SETUP" --rolle prod --dns cloudflare --email admin@example.at)"; rc=$?
[ $rc -eq 0 ]; behaupte "Prod/Cloudflare: Einrichtung endet mit 0" $?
grep -q "ufw allow 80/tcp" "$w/zustand/log" && grep -q "ufw allow 443/tcp" "$w/zustand/log"; behaupte "Prod: 80/443 öffentlich" $?
grep -q "^BIND_IP=0.0.0.0$" "$w/opt/edge/.env"; behaupte "Prod: Edge ausdrücklich auf allen Adressen (0.0.0.0)" $?
cmp -s "$w/var/lib/corevision/geoblock/regeln.nft" "$w/zustand/nft-geladen"; behaupte "Prod: Geoblocking auch vor den öffentlichen Ports 80/443" $?
grep -q "^ZIEL_IP=203.0.113.10$" "$w/etc/corevision/server.env"; behaupte "Prod: A-Records auf die öffentliche IPv4" $?
grep -q "dns cloudflare {env.DNS_API_TOKEN}" "$w/opt/edge/caddy/Caddyfile" && grep -q "resolvers 1.1.1.1" "$w/opt/edge/caddy/Caddyfile"; behaupte "Prod: Caddyfile mit Cloudflare-DNS-01" $?

# --- acme-dns: kein Token nötig, kein tls_dns-Baustein
w="$(neue_welt acmedns)"
out="$(TS_IP=100.64.0.7 lauf "$w" "$SETUP" --rolle prod --dns acmedns --email admin@example.at)"; rc=$?
[ $rc -eq 0 ]; behaupte "acme-dns: Einrichtung ohne Token endet mit 0" $?
grep -q "^ACMEDNS_URL=https://auth.acme-dns.io$" "$w/etc/corevision/server.env" && printf '%s' "$out" | grep -q "öffentlichen Testdienst"; behaupte "acme-dns: Vorgabe Testdienst mit Warnung" $?
grep -q "tls_dns" "$w/opt/edge/caddy/Caddyfile"; [ $? -ne 0 ]; behaupte "acme-dns: kein gemeinsamer DNS-Baustein" $?

# --- edge-site
w_dev="$tmp/dev"; w_prod="$tmp/prod"; w_acme="$tmp/acmedns"
lauf "$w_dev" "$SITE" add "App.Example.at" app:8080 >/dev/null; [ $? -eq 1 ]; behaupte "edge-site: ungültiger Hostname endet mit 1" $?
lauf "$w_dev" "$SITE" add app.example.at app >/dev/null; [ $? -eq 1 ]; behaupte "edge-site: Ziel ohne Port endet mit 1" $?
lauf "$w_dev" "$SITE" frag >/dev/null; [ $? -eq 1 ]; behaupte "edge-site: unbekannter Befehl endet mit 1" $?
lauf "$w_dev" "$SITE" remove "../caddy/x" >/dev/null; [ $? -eq 1 ]; behaupte "edge-site: remove prüft den Hostnamen (kein ../)" $?
if [ $hat_jq -eq 1 ]; then
    out="$(lauf "$w_dev" "$SITE" add app.example.at app-dev-app:8080)"; rc=$?
    [ $rc -eq 0 ] && [ -f "$w_dev/opt/edge/caddy/sites/dev.app.example.at.caddy" ]; behaupte "edge-site Dev: Site unter dev.<host>" $?
    grep -q "import tls_dns" "$w_dev/opt/edge/caddy/sites/dev.app.example.at.caddy" && grep -q "reverse_proxy app-dev-app:8080" "$w_dev/opt/edge/caddy/sites/dev.app.example.at.caddy"; behaupte "edge-site Dev: Site mit DNS-01 und Ziel" $?
    grep -q 'hetzner.cloud/v1/zones/example.at/rrsets$' "$w_dev/zustand/log" && grep -q '"name":"dev.app","type":"A","ttl":300,"records":\[{"value":"100.64.0.5"}\]' "$w_dev/zustand/log"; behaupte "edge-site Dev: A-Record dev.app → Tailscale-IP über die Hetzner-API" $?
    lauf "$w_dev" "$SITE" add app.example.at app-dev-app:8080 >/dev/null
    grep -q "rrsets/dev.app/A/actions/set_records" "$w_dev/zustand/log"; behaupte "edge-site Dev: zweiter Aufruf ersetzt den A-Record statt ihn doppelt anzulegen" $?
    lauf "$w_dev" "$SITE" list | grep -q "app.example.at app-dev-app:8080"; behaupte "edge-site: list zeigt die Site" $?
    # Kopfzeilen bleiben an: Die CI validiert die erzeugte Site mit dem echten Caddy (Syntax `?`).
    lauf "$w_dev" "$SITE" kopfzeilen app.example.at an --csp "default-src 'self'; frame-ancestors 'self'" >/dev/null
    lauf "$w_dev" "$SITE" add app.example.at app-dev-app:8080 >/dev/null
    grep -q '# edge-site: kopfzeilen an' "$w_dev/opt/edge/caddy/sites/dev.app.example.at.caddy" \
        && grep -q "header ?Content-Security-Policy \"default-src 'self'; frame-ancestors 'self'\"" "$w_dev/opt/edge/caddy/sites/dev.app.example.at.caddy"
    behaupte "edge-site: erneutes add behält Kopfzeilen und CSP" $?
    touch "$w_dev/zustand/validate-fehler"
    lauf "$w_dev" "$SITE" add neu.example.at neu:8080 >/dev/null; rc=$?
    [ $rc -eq 1 ] && [ ! -f "$w_dev/opt/edge/caddy/sites/dev.neu.example.at.caddy" ]; behaupte "edge-site: abgelehnte Konfiguration wird zurückgenommen" $?
    rm -f "$w_dev/zustand/validate-fehler"

    lauf "$w_prod" "$SITE" add shop.example.at shop-app:8080 >/dev/null; rc=$?
    [ $rc -eq 0 ] && [ -f "$w_prod/opt/edge/caddy/sites/shop.example.at.caddy" ]; behaupte "edge-site Prod: Site ohne dev.-Präfix" $?
    grep -q 'cloudflare.com/client/v4/zones/z1/dns_records' "$w_prod/zustand/log" && grep -q '"proxied":false' "$w_prod/zustand/log"; behaupte "edge-site Prod: A-Record über die Cloudflare-API, ohne Proxy" $?

    out="$(lauf "$w_acme" "$SITE" add info.example.at info-app:8080)"; rc=$?
    [ $rc -eq 0 ] && printf '%s' "$out" | grep -q "_acme-challenge.info.example.at CNAME s1.auth.acme-dns.io."; behaupte "edge-site acme-dns: CNAME-Anweisung genau ausgegeben" $?
    grep -q "dns acmedns /etc/caddy/acmedns/info.example.at.json" "$w_acme/opt/edge/caddy/sites/info.example.at.caddy"; behaupte "edge-site acme-dns: Site nutzt die eigenen Zugangsdaten" $?
    grep -q '"server_url": "https://auth.acme-dns.io"' "$w_acme/opt/edge/caddy/acmedns/info.example.at.json"; behaupte "edge-site acme-dns: Zugangsdaten mit Server gespeichert" $?
    : > "$w_acme/zustand/log"; lauf "$w_acme" "$SITE" add info.example.at info-app:8080 >/dev/null
    grep -q "/register" "$w_acme/zustand/log"; [ $? -ne 0 ]; behaupte "edge-site acme-dns: zweiter Aufruf registriert nicht erneut" $?

    lauf "$w_prod" "$SITE" remove shop.example.at >/dev/null; rc=$?
    [ $rc -eq 0 ] && [ ! -f "$w_prod/opt/edge/caddy/sites/shop.example.at.caddy" ]; behaupte "edge-site: remove entfernt die Site" $?
else
    echo "skip   edge-site: Fälle mit DNS-API (jq fehlt hier; läuft in der CI)"
fi

# --- edge-site kopfzeilen: je Site aus, bis man sie einschaltet (ohne DNS-API, läuft überall)
w_kopf="$tmp/kopf"; site="$w_kopf/opt/edge/caddy/sites/web.example.at.caddy"
mkdir -p "$w_kopf/etc/corevision" "$w_kopf/opt/edge/caddy/sites" "$w_kopf/zustand"
printf 'ROLLE=prod\nDNS=hetzner\nZIEL_IP=203.0.113.10\n' > "$w_kopf/etc/corevision/server.env"
printf '# edge-site add web.example.at web-app:8080\nweb.example.at {\n\timport tls_dns\n\tencode zstd gzip\n\treverse_proxy web-app:8080\n}\n' > "$site"
cp "$site" "$tmp/site-vorher"
lauf "$w_kopf" "$SITE" kopfzeilen web.example.at vielleicht >/dev/null; [ $? -eq 1 ]; behaupte "kopfzeilen: nur an oder aus" $?
lauf "$w_kopf" "$SITE" kopfzeilen fremd.example.at an >/dev/null; [ $? -eq 1 ]; behaupte "kopfzeilen: unbekannte Site endet mit 1" $?
lauf "$w_kopf" "$SITE" check web.example.at | grep -q '^   aus     Kopfzeilen'; behaupte "kopfzeilen: ohne Schalter aus, check nennt es" $?
lauf "$w_kopf" "$SITE" kopfzeilen web.example.at an >/dev/null; rc=$?
[ $rc -eq 0 ] && grep -q $'^\theader ?Strict-Transport-Security "max-age=31536000"$' "$site" && ! grep -q 'includeSubDomains\|preload' "$site" \
    && grep -q $'^\theader ?X-Content-Type-Options "nosniff"$' "$site" && ! grep -q 'Content-Security-Policy' "$site"
behaupte "kopfzeilen an: HSTS ein Jahr ohne Subdomains, nosniff, ohne CSP" $?
# Je Kopf eine header-Zeile, kein header-Block: In einem Block prüft Caddy alle `?`-Felder
# gemeinsam und setzt keines, sobald die Anwendung auch nur eines davon schickt.
! grep -q 'header {' "$site" && [ "$(grep -c $'^\theader ?' "$site")" -eq 5 ]
behaupte "kopfzeilen an: je Kopf eine eigene header-Zeile" $?
awk '/encode zstd gzip/{e=NR} /# edge-site: kopfzeilen an/{k=NR} /reverse_proxy/{r=NR} END{exit !(e<k && k<r)}' "$site"
behaupte "kopfzeilen an: Block steht in der Site zwischen encode und reverse_proxy" $?
lauf "$w_kopf" "$SITE" kopfzeilen web.example.at an >/dev/null
[ "$(grep -c '# edge-site: kopfzeilen an' "$site")" -eq 1 ]; behaupte "kopfzeilen an: zweimal geschaltet, ein Block" $?
lauf "$w_kopf" "$SITE" list | grep -q 'web.example.at web-app:8080  (Kopfzeilen an)'; behaupte "kopfzeilen: list zeigt den Zustand" $?
lauf "$w_kopf" "$SITE" check web.example.at | grep -q 'FEHLT   Kopfzeilen: an, aber kein Strict-Transport-Security'
behaupte "kopfzeilen: check merkt, wenn HSTS nicht ankommt" $?
touch "$w_kopf/zustand/hsts"
lauf "$w_kopf" "$SITE" check web.example.at | grep -q 'ok      Kopfzeilen: an, HSTS kommt an'; behaupte "kopfzeilen: check bestätigt HSTS" $?
lauf "$w_kopf" "$SITE" kopfzeilen web.example.at an --csp "default-src 'self'" >/dev/null
grep -q "header ?Content-Security-Policy \"default-src 'self'\"" "$site"; behaupte "kopfzeilen an --csp: Richtlinie wörtlich, nur als Vorgabe (?)" $?
lauf "$w_kopf" "$SITE" kopfzeilen web.example.at an >/dev/null
grep -q "header ?Content-Security-Policy \"default-src 'self'\"" "$site"; behaupte "kopfzeilen an ohne --csp: vorhandene CSP bleibt" $?
cp "$site" "$tmp/site-mit-csp"
for boese in 'x" }' '{$GEHEIM}' 'a\b' '' $'a\nb' $'a\rb'; do
    lauf "$w_kopf" "$SITE" kopfzeilen web.example.at an --csp "$boese" >/dev/null; rc=$?
    [ $rc -eq 1 ] && cmp -s "$site" "$tmp/site-mit-csp"; behaupte "kopfzeilen --csp: „$boese“ abgewiesen, Site unverändert" $?
done
touch "$w_kopf/zustand/validate-fehler"
lauf "$w_kopf" "$SITE" kopfzeilen web.example.at aus >/dev/null; rc=$?
[ $rc -eq 1 ] && cmp -s "$site" "$tmp/site-mit-csp"; behaupte "kopfzeilen: abgelehnte Konfiguration wird zurückgenommen" $?
rm -f "$w_kopf/zustand/validate-fehler"
lauf "$w_kopf" "$SITE" kopfzeilen web.example.at aus >/dev/null; rc=$?
[ $rc -eq 0 ] && cmp -s "$site" "$tmp/site-vorher"; behaupte "kopfzeilen aus: Site-Datei genau wie vorher" $?
# Von Hand geänderte Site ohne Ankerzeile: kein stilles „ok“ ohne Block.
printf '# edge-site add web.example.at web-app:8080\nweb.example.at {\n\treverse_proxy web-app:8080\n}\n' > "$site"
cp "$site" "$tmp/site-ohne-anker"
lauf "$w_kopf" "$SITE" kopfzeilen web.example.at an >/dev/null; rc=$?
[ $rc -eq 1 ] && cmp -s "$site" "$tmp/site-ohne-anker"; behaupte "kopfzeilen an: Site ohne Ankerzeile abgewiesen, unverändert" $?
lauf "$w_kopf" "$SITE" kopfzeilen $'web.example.at\n../../x' an >/dev/null; [ $? -eq 1 ]
behaupte "edge-site: Hostname mit Zeilenumbruch wird abgewiesen" $?

# --- geoblock: Länder, Ausnahmen, unplausible Listen, Aussperrschutz, fail-closed
GB="$HERE/geoblock"
bash -n "$GB"; behaupte "geoblock: Syntax" $?
w="$(neue_welt geo)"
gb_regeln="$w/var/lib/corevision/geoblock/regeln.nft"; gb_ausn="$w/etc/corevision/geoblock-ausnahmen"
lauf "$w" "$GB" --help | grep -q "IP Geolocation by DB-IP"; behaupte "geoblock: --help nennt Aufruf und Quelle (CC BY 4.0)" $?
lauf "$w" "$GB" >/dev/null; [ $? -eq 1 ]; behaupte "geoblock: ohne Befehl endet mit 1" $?
lauf "$w" "$GB" aktualisieren | grep -q "nicht eingerichtet"; behaupte "geoblock aktualisieren: vor einrichten abgelehnt" $?
lauf "$w" "$GB" einrichten --laender A1 >/dev/null; [ $? -eq 1 ]; behaupte "geoblock: ungültiger Ländercode endet mit 1" $?
lauf "$w" "$GB" einrichten --dry-run >/dev/null
[ ! -e "$w/etc/corevision" ] && [ ! -e "$w/etc/systemd" ] && [ ! -e "$w/var/lib" ]; behaupte "geoblock einrichten --dry-run: schreibt nichts" $?
out="$(lauf "$w" "$GB" einrichten --laender XX)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "Land XX kommt in der Länderliste nicht vor" \
    && [ ! -f "$w/etc/corevision/geoblock.conf" ] && ! grep -q "nft -f" "$w/zustand/log"; behaupte "geoblock: Land fehlt in der Liste → nichts geschrieben, nichts geladen" $?
touch "$w/zustand/dbip-fehlt-$(date -u +%Y-%m)"
out="$(lauf "$w" "$GB" einrichten --laender at,de)"; rc=$?
[ $rc -eq 0 ] && grep -q "dbip-country-lite-$(date -u -d "$(date -u +%Y-%m-01) -1 month" +%Y-%m).csv.gz" "$w/zustand/log"; behaupte "geoblock: Datei des Monats fehlt → die des Vormonats" $?
grep -q "^LAENDER=AT,DE$" "$w/etc/corevision/geoblock.conf" && printf '%s' "$out" | grep -q "Abweichung vom Standard" \
    && ! grep -q "203.0.113.192" "$gb_regeln"; behaupte "geoblock --laender at,de: nur AT und DE, Abweichung gemeldet" $?
lauf "$w" "$GB" einrichten --laender AT,CH,LI,DE >/dev/null
: > "$w/zustand/log"
out="$(lauf "$w" "$GB" einrichten)"; rc=$?
[ $rc -eq 0 ] && ! printf '%s' "$out" | grep -q "   mache " && ! grep -q "nft -f" "$w/zustand/log"; behaupte "geoblock einrichten: zweiter Lauf ändert und lädt nichts" $?
w2="$(neue_welt geo-ohne-liste)"; rm "$w2/zustand/dbip.csv.gz"
out="$(lauf "$w2" "$GB" einrichten)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "nicht abrufbar" && [ ! -f "$w2/etc/corevision/geoblock.conf" ]; behaupte "geoblock: keine Länderliste erreichbar → nichts eingerichtet, Exit ≠ 0" $?

# Unplausible Listen: Die geladene Sperre bleibt
cp "$w/zustand/nft-geladen" "$tmp/geladen-vorher"; cp "$w/zustand/dbip.csv.gz" "$tmp/dbip-gut"
head -c 60 "$tmp/dbip-gut" > "$w/zustand/dbip.csv.gz"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "beschädigt" && cmp -s "$w/zustand/nft-geladen" "$tmp/geladen-vorher"; behaupte "geoblock aktualisieren: beschädigte Liste abgelehnt, geladene bleibt" $?
gzip -dc "$tmp/dbip-gut" | grep -v ",LI$" | gzip > "$w/zustand/dbip.csv.gz"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "Land LI kommt" && cmp -s "$w/zustand/nft-geladen" "$tmp/geladen-vorher"; behaupte "geoblock aktualisieren: Land fehlt → abgelehnt, geladene bleibt" $?
cp "$tmp/dbip-gut" "$w/zustand/dbip.csv.gz"; stand="$w/var/lib/corevision/geoblock/stand"; cp "$stand" "$tmp/stand-gut"
sed 's/^ANZAHL4=.*/ANZAHL4=100/' "$tmp/stand-gut" > "$stand"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "nur 5 Bereiche statt bisher 101"; behaupte "geoblock aktualisieren: weniger als die Hälfte der Bereiche → abgelehnt" $?
sed 's/^ANZAHL4=.*/ANZAHL4=1/; s/^ANZAHL6=.*/ANZAHL6=0/' "$tmp/stand-gut" > "$stand"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "mehr als doppelt so viele"; behaupte "geoblock aktualisieren: mehr als doppelt so viele Bereiche → abgelehnt" $?
sed 's/^ADRESSEN4=.*/ADRESSEN4=10/' "$tmp/stand-gut" > "$stand"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "225 IPv4-Adressen statt bisher 10"; behaupte "geoblock aktualisieren: IPv4-Abdeckung wächst um mehr als die Hälfte → abgelehnt" $?
cp "$tmp/stand-gut" "$stand"
# Was aus dem Netz kommt, landet als root in der Firewall: keine fremde nft-Syntax, keine Welt-Bereiche
{ gzip -dc "$tmp/dbip-gut"; printf '%s\n' '9.9.9.9 } } flush ruleset ; table inet x { set y { type ipv4_addr; elements = { 9.9.9.9,9.9.9.10,AT'; } | gzip > "$w/zustand/dbip.csv.gz"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "fehlerhafte Zeilen" && cmp -s "$w/zustand/nft-geladen" "$tmp/geladen-vorher"; behaupte "geoblock aktualisieren: nft-Syntax in der Liste → ganze Liste abgelehnt" $?
{ gzip -dc "$tmp/dbip-gut"; printf '%s\n' '0.0.0.0,255.255.255.255,AT'; } | gzip > "$w/zustand/dbip.csv.gz"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "fehlerhafte Zeilen"; behaupte "geoblock aktualisieren: Bereich größer als /8 → ganze Liste abgelehnt" $?
# awk läse „3e3“ als Zahl 3000 — der Block wird hexadezimal verglichen, der Bereich verworfen
{ gzip -dc "$tmp/dbip-gut"; printf '%s\n' '3e3::,3000:ffff:ffff:ffff:ffff:ffff:ffff:ffff,AT'; } | gzip > "$w/zustand/dbip.csv.gz"
lauf "$w" "$GB" aktualisieren >/dev/null; rc=$?
[ $rc -eq 0 ] && ! grep -qi "3e3::" "$w/zustand/nft-geladen"; behaupte "geoblock aktualisieren: IPv6-Bereich über mehrere Blöcke (3e3:: bis 3000::) verworfen" $?
{ gzip -dc "$tmp/dbip-gut"; printf '%s\n' '2001:1000::,2001:ffff:ffff:ffff:ffff:ffff:ffff:ffff,AT'; } | gzip > "$w/zustand/dbip.csv.gz"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "IPv6-/32-Blöcke statt bisher 1"; behaupte "geoblock aktualisieren: IPv6-Abdeckung wächst um mehr als die Hälfte → abgelehnt" $?
cp "$tmp/dbip-gut" "$w/zustand/dbip.csv.gz"
# Ohne SSH_CONNECTION (systemd-Timer): kein Abbruch an set -u
: > "$w/zustand/log"
out="$(env -i PATH="$tmp/bin:$S" SERVER_WURZEL="$w" ZUSTAND="$w/zustand" "$BASH_BIN" "$GB" aktualisieren 2>&1)"; rc=$?
[ $rc -eq 0 ] && ! printf '%s' "$out" | grep -q "unbound"; behaupte "geoblock aktualisieren: läuft ohne SSH_CONNECTION wie unter systemd" $?
cp "$w/zustand/nft-geladen" "$tmp/geladen-vorher"
touch "$w/zustand/nft-ungueltig"; cp "$gb_ausn" "$tmp/ausnahmen-vorher"
out="$(lauf "$w" "$GB" erlauben 198.51.100.0/28 --grund "Probe")"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "nft lehnt" && cmp -s "$gb_ausn" "$tmp/ausnahmen-vorher"; behaupte "geoblock: nft -c lehnt ab → nichts geladen, Ausnahmen unverändert" $?
rm "$w/zustand/nft-ungueltig"

# Ausnahmen: nur mit Grund, nur gültige Netze und bekannte Dienste
lauf "$w" "$GB" erlauben 198.51.100.0/28 >/dev/null; [ $? -eq 1 ]; behaupte "geoblock erlauben: ohne --grund abgelehnt" $?
lauf "$w" "$GB" erlauben 0.0.0.0/0 --grund x >/dev/null; [ $? -eq 1 ]; behaupte "geoblock erlauben: 0.0.0.0/0 abgelehnt — Länder über --laender" $?
lauf "$w" "$GB" erlauben ::/0 --grund x >/dev/null; [ $? -eq 1 ]; behaupte "geoblock erlauben: ::/0 abgelehnt" $?
lauf "$w" "$GB" erlauben 300.1.1.0/24 --grund x >/dev/null; [ $? -eq 1 ]; behaupte "geoblock erlauben: ungültige Adresse abgelehnt" $?
lauf "$w" "$GB" erlauben dienst:unbekannt --grund x >/dev/null; [ $? -eq 1 ]; behaupte "geoblock erlauben: unbekannter Dienst abgelehnt" $?
lauf "$w" "$GB" erlauben $'2001:db8::/32\n::/0\n2001:db8::/32' --grund x >/dev/null; [ $? -eq 1 ] && ! grep -q "::/0" "$gb_ausn"; behaupte "geoblock erlauben: Zeilenumbruch im Netz abgelehnt (kein zweiter Eintrag ohne Prüfung)" $?
out="$(lauf "$w" "$GB" erlauben 198.51.100.0/28 --grund "ADR 0004 shop: Webhook")"; rc=$?
[ $rc -eq 0 ] && grep -q "^198.51.100.0/28  # ADR 0004 shop: Webhook ($(date +%F), root)$" "$gb_ausn" \
    && set_von "$w/zustand/nft-geladen" ausnahmen4 | grep -q "198.51.100.0/28"; behaupte "geoblock erlauben: Netz mit Grund eingetragen und geladen" $?
grep -q "^erlaubt: 198.51.100.0/28 — ADR 0004 shop: Webhook (root)$" "$w/zustand/journal"; behaupte "geoblock erlauben: Änderung steht im Journal (wer, was, warum)" $?
lauf "$w" "$GB" erlauben 198.51.100.0/28 --grund "nochmal" | grep -q "schon erlaubt" && [ "$(grep -c '^198.51.100.0/28' "$gb_ausn")" -eq 1 ]; behaupte "geoblock erlauben: zweimal → ein Eintrag" $?
out="$(lauf "$w" "$GB" erlauben dienst:stripe-webhooks --grund "ADR 0005 shop: Stripe")"; rc=$?
[ $rc -eq 0 ] && set_von "$w/zustand/nft-geladen" ausnahmen4 | grep -q "3.18.12.63," && ! grep -q $'\r' "$w/zustand/nft-geladen"; behaupte "geoblock erlauben dienst:stripe-webhooks: Adressliste geladen, CRLF bereinigt" $?
if [ $hat_jq -eq 1 ]; then
    lauf "$w" "$GB" erlauben dienst:googlebot --grund "ADR 0006 website: Index" >/dev/null
    set_von "$w/zustand/nft-geladen" ausnahmen4 | grep -q "66.249.64.0/27" && set_von "$w/zustand/nft-geladen" ausnahmen6 | grep -q "2001:4860:4801:10::/64"
    behaupte "geoblock erlauben dienst:googlebot: IPv4- und IPv6-Präfixe aus der JSON-Liste" $?
else echo "übersprungen: dienst:googlebot braucht jq (CI)"; fi
touch "$w/zustand/dienst-fehlt"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "letzter Stand bleibt" && set_von "$w/zustand/nft-geladen" ausnahmen4 | grep -q "3.18.12.63"; behaupte "geoblock aktualisieren: Dienstliste nicht abrufbar → letzter Stand, Exit ≠ 0" $?
rm "$w/zustand/dienst-fehlt"
lauf "$w" "$GB" erlauben dienst:uptimerobot --grund "ADR 0007 shop: Monitoring" >/dev/null
set_von "$w/zustand/nft-geladen" ausnahmen4 | grep -q "5.6.7.8" && ! grep -qE "0\.0\.0\.0/0|::/0|1\.2\.3\.0/8" "$w/zustand/nft-geladen"; behaupte "geoblock: zu weite Einträge einer Dienstliste verworfen (IPv4 ab /16)" $?
cp "$gb_ausn" "$tmp/ausnahmen-vorher"; cp "$w/zustand/nft-geladen" "$tmp/geladen-vorher"
printf '0.0.0.0/0  # von Hand\n' >> "$gb_ausn"
out="$(lauf "$w" "$GB" aktualisieren)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "Ungültige Ausnahme" && cmp -s "$w/zustand/nft-geladen" "$tmp/geladen-vorher"; behaupte "geoblock: von Hand eingetragenes 0.0.0.0/0 hält alles an, nichts geladen" $?
cp "$tmp/ausnahmen-vorher" "$gb_ausn"
lauf "$w" "$GB" liste | grep -q "ADR 0004 shop: Webhook"; behaupte "geoblock liste: Ausnahmen mit Grund" $?
lauf "$w" "$GB" entfernen 198.51.100.0/28 >/dev/null
! grep -q "198.51.100.0/28" "$gb_ausn" && ! grep -q "198.51.100.0/28" "$w/zustand/nft-geladen" && grep -q "^entfernt: 198.51.100.0/28 (root)$" "$w/zustand/journal"
behaupte "geoblock entfernen: Netz ausgetragen, nicht mehr geladen, im Journal" $?

# Aussperrschutz: eigene SSH-Sitzung aus einer Adresse, die danach gesperrt wäre
echo 198.51.100.7 > "$w/zustand/nft-fremd"; cp "$w/zustand/nft-geladen" "$tmp/geladen-vorher"
out="$(SSH_CONNECTION="198.51.100.7 5000 203.0.113.10 22" lauf "$w" "$GB" erlauben 192.0.2.0/24 --grund x)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "zurückgerollt" && cmp -s "$w/zustand/nft-geladen" "$tmp/geladen-vorher" \
    && ! grep -q "192.0.2.0/24" "$gb_ausn"; behaupte "Aussperrschutz: Sitzung wäre gesperrt → zurückgerollt, nichts eingetragen" $?
out="$(SSH_CONNECTION="198.51.100.7 5000 203.0.113.10 22" lauf "$w" "$GB" erlauben 192.0.2.0/24 --grund x --force)"; rc=$?
[ $rc -eq 0 ] && printf '%s' "$out" | grep -q "ab jetzt gesperrt (--force)"; behaupte "Aussperrschutz: --force übergeht bewusst" $?
echo 100.100.1.2 >> "$w/zustand/nft-fremd"
SSH_CONNECTION="100.100.1.2 5000 100.64.0.5 22" lauf "$w" "$GB" entfernen 192.0.2.0/24 >/dev/null; behaupte "Aussperrschutz: Sitzung über das Tailnet ist nie betroffen" $?
# Unter sudo fehlt SSH_CONNECTION ganz: Die Gegenstelle kommt dann aus `who -m`
printf 'admin    pts/0        2026-09-29 12:00 (198.51.100.7)\n' > "$w/zustand/who"
out="$(env -i PATH="$tmp/bin:$S" SERVER_WURZEL="$w" ZUSTAND="$w/zustand" "$BASH_BIN" "$GB" erlauben 192.0.2.0/24 --grund x 2>&1)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "zurückgerollt" && ! printf '%s' "$out" | grep -q "unbound" && ! grep -q "192.0.2.0/24" "$gb_ausn"
behaupte "Aussperrschutz: ohne SSH_CONNECTION (sudo) über who -m, zurückgerollt" $?
rm "$w/zustand/who"
cp "$w/etc/corevision/geoblock.conf" "$tmp/konf-vorher"
out="$(SSH_CONNECTION="198.51.100.7 5000 203.0.113.10 22" lauf "$w" "$GB" einrichten --laender AT,DE)"; rc=$?
[ $rc -ne 0 ] && cmp -s "$w/etc/corevision/geoblock.conf" "$tmp/konf-vorher" && [ ! -f "$w/etc/corevision/geoblock.conf.alt" ]; behaupte "Aussperrschutz in einrichten: auch die Länder-Konfiguration zurückgerollt" $?
rm "$w/zustand/nft-fremd"

# Start ohne gespeicherte Regeln: fail-closed; check meldet es, aktualisieren behebt es
rm "$gb_regeln"
out="$(lauf "$w" "$GB" laden)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "alles Öffentliche ist gesperrt" && grep -q 'iifname { "lo", "tailscale0" } accept' "$w/zustand/nft-geladen" \
    && ! grep -q "elements" "$w/zustand/nft-geladen"; behaupte "geoblock laden ohne Regeln: keine Länder, Tailnet frei, Exit ≠ 0 (fail-closed)" $?
echo 198.51.100.7 > "$w/zustand/nft-fremd"
SSH_CONNECTION="198.51.100.7 5000 203.0.113.10 22" lauf "$w" "$GB" aktualisieren >/dev/null; rc=$?
[ $rc -ne 0 ] && cmp -s "$w/var/lib/corevision/geoblock/gesperrt.nft" "$w/zustand/nft-geladen"; behaupte "Aussperrschutz bei gesperrter Tabelle: zurück auf die gesperrte Fassung, nicht offen" $?
rm "$w/zustand/nft-fremd"
out="$(lauf "$w" "$GB" check)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "keine gültige Länderliste" && printf '%s' "$out" | grep -q "ohne Länder geladen"; behaupte "geoblock check: ohne gespeicherte Regeln rot, gesperrte Tabelle erkannt" $?
lauf "$w" "$GB" aktualisieren >/dev/null; lauf "$w" "$GB" check >/dev/null; behaupte "geoblock aktualisieren behebt es, check grün" $?
touch "$w/zustand/an-nftables.service"
lauf "$w" "$GB" check | grep -q "nftables.service ist eingeschaltet"; behaupte "geoblock check: eingeschaltetes nftables.service → rot (flush ruleset)" $?
rm "$w/zustand/an-nftables.service"
lauf "$w" "$GB" waechter >/dev/null; behaupte "geoblock waechter: Tabelle geladen → still, Exit 0" $?
rm "$w/zustand/nft-geladen"
out="$(lauf "$w" "$GB" waechter)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "fehlte — neu geladen" && cmp -s "$gb_regeln" "$w/zustand/nft-geladen"; behaupte "geoblock waechter: Tabelle verschwunden → nachgeladen, Exit ≠ 0 fürs Journal" $?
out="$(lauf "$w" "$GB" check)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "FEHLT   Der Wächter musste die Sperre"; behaupte "geoblock check: Nachladen durch den Wächter bleibt eine Woche rot" $?
rm "$w/var/lib/corevision/geoblock/nachgeladen"
touch "$w/zustand/gescheitert-corevision-geoblock.service"
out="$(lauf "$w" "$GB" check)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "FEHLT   corevision-geoblock.service ist beim Start gescheitert"; behaupte "geoblock check: gescheiterter Start-Dienst → rot" $?
rm "$w/zustand/gescheitert-corevision-geoblock.service"
touch -d '50 days ago' "$w/var/lib/corevision/geoblock/dbip-country-lite.csv.gz"
out="$(lauf "$w" "$GB" check)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "FEHLT   Länderliste 50 Tage alt"; behaupte "geoblock check: Liste älter als 45 Tage → rot" $?

# Prod ohne Geoblocking: Der Edge geht nicht ans Netz
w="$(neue_welt prod-ohne-geo)"; rm "$w/zustand/dbip.csv.gz"
out="$(TS_IP=100.64.0.6 SSH_CONNECTION="100.64.0.9 5000 100.64.0.6 22" DNS_API_TOKEN=cf lauf "$w" "$SETUP" --rolle prod --dns cloudflare --email admin@example.at)"; rc=$?
[ $rc -ne 0 ] && printf '%s' "$out" | grep -q "Edge startet auf Prod erst" && ! grep -q "up -d --build" "$w/zustand/log"; behaupte "Prod: ohne Geoblocking startet der Edge nicht, Exit ≠ 0" $?

# --- rollout: nur auf Auftrag, sofort oder zum Termin, fester Tag
RO="$HERE/rollout"
bash -n "$RO"; behaupte "rollout: Syntax" $?
# GitHub-Attrappe: Releases v1.2.0 und v1.3.0; der Tarball enthält compose.yaml und deploy/update.sh.
stub "$S" curl-github 'true'
gh_quelle="$tmp/gh-quelle/app-abc123"; mkdir -p "$gh_quelle/deploy"
printf 'name: app\n' > "$gh_quelle/compose.yaml"
printf '#!%s\necho "update.sh $1" >> "$ZUSTAND/log"; [ ! -f "$ZUSTAND/update-fehler" ]\n' "$BASH_BIN" > "$gh_quelle/deploy/update.sh"; chmod +x "$gh_quelle/deploy/update.sh"
( cd "$tmp/gh-quelle" && tar -czf "$tmp/quelle.tar.gz" app-abc123 )
stub "$S" curl 'echo "curl $*" >> "$ZUSTAND/log"
# Wie das echte curl: Mit -H @- kommt der Authorization-Header über stdin.
case " $* " in *" @- "*) cat > /dev/null;; esac
out=""; url=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; case "$a" in http*) url="$a";; esac; prev="$a"; done
case "$url" in
  *api.github.com/repos/*/releases/latest) printf "{\n  \"tag_name\": \"v1.3.0\",\n  \"name\": \"v1.3.0\"\n}\n";;
  *api.github.com/repos/*/releases/tags/v1.2.0|*api.github.com/repos/*/releases/tags/v1.3.0) echo "{}";;
  *api.github.com/repos/*/releases/tags/*) exit 22;;
  *api.github.com/repos/*/tarball/*) cp "'"$tmp"'/quelle.tar.gz" "$out";;
  *) [ -n "$out" ] && : > "$out"; echo "{}";;
esac'
for w in tar gzip date; do p="$(command -v "$w")" && printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$p" > "$tmp/bin/$w" && chmod +x "$tmp/bin/$w"; done
w_ro="$tmp/prod"; mkdir -p "$w_ro/opt/apps"; : > "$w_ro/zustand/log"
ro() { ROLLOUT_BEFEHL=/usr/local/bin/rollout lauf "$@"; }
einheit_von() { for t in "$w_ro"/etc/systemd/system/rollout-app-*.timer; do [ -f "$t" ] && { basename "$t" .timer; return; }; done; }

ro "$tmp/dev" "$RO" app jetzt | grep -q "nur auf dem Prod-Server"; behaupte "rollout: auf Dev abgelehnt" $?
ro "$w_ro" "$RO" app jetzt | grep -q "nicht angemeldet"; behaupte "rollout: nicht angemeldete Anwendung abgelehnt" $?
ro "$w_ro" "$RO" app einrichten CoreVision-Systems-GmbH/app | grep -q "GitHub-Token fehlt"; behaupte "rollout: ohne Token abgelehnt" $?
grep -q "^REPO=CoreVision-Systems-GmbH/app$" "$w_ro/opt/apps/app/rollout.conf"; behaupte "rollout: einrichten merkt sich das Repo" $?
printf 'ghp_test\n' | env -i PATH="$tmp/bin:$S" SERVER_WURZEL="$w_ro" ZUSTAND="$w_ro/zustand" "$BASH_BIN" "$RO" token >/dev/null 2>&1
grep -q "^ghp_test$" "$w_ro/etc/corevision/github-token"; behaupte "rollout: token liest von stdin, nicht aus Argumenten" $?
: > "$w_ro/zustand/log"
out="$(ro "$w_ro" "$RO" app einrichten CoreVision-Systems-GmbH/app)"; rc=$?
[ $rc -eq 0 ] && [ -f "$w_ro/opt/apps/app/compose.yaml" ] && [ -x "$w_ro/opt/apps/app/deploy/update.sh" ]; behaupte "rollout einrichten: Lieferdateien des neuesten Releases für die Erstinstallation" $?
grep -q "update.sh" "$w_ro/zustand/log"; [ $? -ne 0 ] && printf '%s' "$out" | grep -q "deploy/install.sh"; behaupte "rollout einrichten: startet nichts, nennt deploy/install.sh" $?
ro "$w_ro" "$RO" app jetzt | grep -q ".env fehlt"; behaupte "rollout jetzt: ohne .env (vor der Erstinstallation) abgelehnt" $?
printf 'APP_VERSION=1.2.0\nGEHEIM=bleibt\n' > "$w_ro/opt/apps/app/.env"

out="$(ro "$w_ro" "$RO" app jetzt)"; rc=$?
[ $rc -eq 0 ] && grep -q "^update.sh v1.3.0$" "$w_ro/zustand/log"; behaupte "rollout jetzt: ohne Tag das neueste Release (v1.3.0)" $?
[ -f "$w_ro/opt/apps/app/compose.yaml" ] && grep -q "^GEHEIM=bleibt$" "$w_ro/opt/apps/app/.env"; behaupte "rollout jetzt: Lieferdateien übernommen, .env unberührt" $?
out="$(ro "$w_ro" "$RO" app jetzt 1.2.0)"; rc=$?
[ $rc -eq 0 ] && grep -q "^update.sh v1.2.0$" "$w_ro/zustand/log"; behaupte "rollout jetzt: fester Tag (auch ohne v) — der Rückweg" $?
ro "$w_ro" "$RO" app jetzt v9.9.9 | grep -q "kein Release v9.9.9"; behaupte "rollout jetzt: unbekannter Tag abgelehnt" $?
touch "$w_ro/zustand/update-fehler"
out="$(ro "$w_ro" "$RO" app jetzt)"; rc=$?
[ $rc -ne 0 ] && grep -q "app v1.3.0: GESCHEITERT" "$w_ro/var/log/corevision/rollout.log"; behaupte "rollout jetzt: gescheitertes update.sh endet ≠ 0 und steht im Protokoll" $?
rm -f "$w_ro/zustand/update-fehler"

ro "$w_ro" "$RO" app planen "morgen früh" | grep -q "JJJJ-MM-TT HH:MM"; behaupte "rollout planen: falsches Format abgelehnt" $?
ro "$w_ro" "$RO" app planen "2020-01-01 02:00" | grep -q "nicht in der Zukunft"; behaupte "rollout planen: Termin in der Vergangenheit abgelehnt" $?
termin="$(TZ=Europe/Vienna date -d '+2 days' '+%Y-%m-%d 02:00')"
: > "$w_ro/zustand/log"
out="$(ro "$w_ro" "$RO" app planen "$termin")"; rc=$?
einheit="$(einheit_von)"
[ $rc -eq 0 ] && [ -n "$einheit" ]; behaupte "rollout planen: Termin angelegt" $?
grep -q "^OnCalendar=$termin:00 Europe/Vienna$" "$w_ro/etc/systemd/system/$einheit.timer"; behaupte "rollout planen: Termin in Europe/Vienna" $?
grep -q "ExecStart=/usr/local/bin/rollout app ausfuehren v1.3.0$" "$w_ro/etc/systemd/system/$einheit.service"; behaupte "rollout planen: Tag beim Planen festgeschrieben (v1.3.0)" $?
grep -q "systemctl enable --now $einheit.timer" "$w_ro/zustand/log" && ! grep -q "update.sh" "$w_ro/zustand/log"; behaupte "rollout planen: nur Termin, noch kein Rollout" $?
ro "$w_ro" "$RO" app planen "$termin" | grep -q "schon einen Termin"; behaupte "rollout planen: doppelter Termin abgelehnt" $?
ro "$w_ro" "$RO" liste | grep -q "^${einheit#rollout-} .*app v1.3.0"; behaupte "rollout liste: zeigt Termin, Anwendung und Tag" $?
ro "$w_ro" "$RO" absagen "${einheit#rollout-}" >/dev/null; rc=$?
[ $rc -eq 0 ] && [ ! -f "$w_ro/etc/systemd/system/$einheit.timer" ] && [ ! -f "$w_ro/etc/systemd/system/$einheit.service" ]; behaupte "rollout absagen: Termin entfernt" $?
ro "$w_ro" "$RO" liste | grep -q "Keine Termine"; behaupte "rollout liste: danach leer" $?
ro "$w_ro" "$RO" app planen "$termin" v1.2.0 >/dev/null
einheit="$(einheit_von)"
: > "$w_ro/zustand/log"
ROLLOUT_EINHEIT="$einheit" env -i PATH="$tmp/bin:$S" SERVER_WURZEL="$w_ro" ZUSTAND="$w_ro/zustand" ROLLOUT_EINHEIT="$einheit" "$BASH_BIN" "$RO" app ausfuehren v1.2.0 >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && grep -q "^update.sh v1.2.0$" "$w_ro/zustand/log" && [ ! -f "$w_ro/etc/systemd/system/$einheit.timer" ]; behaupte "rollout: Termin läuft mit festem Tag und räumt sich danach weg" $?

ro "$w_ro" "$RO" app planen "$termin" v1.2.0 >/dev/null
einheit="$(einheit_von)"; touch "$w_ro/zustand/update-fehler"
env -i PATH="$tmp/bin:$S" SERVER_WURZEL="$w_ro" ZUSTAND="$w_ro/zustand" ROLLOUT_EINHEIT="$einheit" "$BASH_BIN" "$RO" app ausfuehren v1.2.0 >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && [ ! -f "$w_ro/etc/systemd/system/$einheit.timer" ]; behaupte "rollout: gescheiterter Termin räumt sich trotzdem weg" $?
rm -f "$w_ro/zustand/update-fehler"
printf '# Termin: 2020-01-01 02:00 Europe/Vienna — app v1.0.0\n' > "$w_ro/etc/systemd/system/rollout-app-202001010200.timer"
ro "$w_ro" "$RO" liste | grep -q "202001010200 .*VERPASST"; behaupte "rollout liste: verpasster Termin gekennzeichnet" $?
rm -f "$w_ro/etc/systemd/system/rollout-app-202001010200.timer"

# Für die CI: die erzeugten Caddy-Konfigurationen ablegen, damit sie im echten Abbild mit
# `caddy validate` geprüft werden (edge-image.yml) — genau das, was die Skripte schreiben.
if [ -n "${SERVER_TEST_ABLAGE:-}" ]; then
    for welt in dev prod acmedns; do
        mkdir -p "$SERVER_TEST_ABLAGE/$welt"; cp -r "$tmp/$welt/opt/edge/caddy/." "$SERVER_TEST_ABLAGE/$welt/"
    done
    # Dazu die systemd-Einheiten des Geoblockings (systemd-analyze verify, Startbefehl mit dash)
    mkdir -p "$SERVER_TEST_ABLAGE/einheiten"; cp "$tmp/dev/etc/systemd/system/"corevision-geoblock* "$SERVER_TEST_ABLAGE/einheiten/"
fi

echo
if [ "$fehler" -eq 0 ]; then echo "Alle Fälle grün."; else echo "Fehler: $fehler"; exit 1; fi
