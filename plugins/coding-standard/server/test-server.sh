#!/usr/bin/env bash
# test-server.sh — prüft setup-server.sh, edge-site und rollout, ohne einen Server anzufassen.
#
# Aufruf:   bash plugins/coding-standard/server/test-server.sh
# Ergebnis: Exit 0, wenn alle Fälle grün sind, sonst Exit 1.
#
# Die Skripte laufen gegen ein Wegwerf-Dateisystem (SERVER_WURZEL) und Attrappen für apt-get,
# dpkg, docker, ufw, tailscale, systemctl, sysctl, ip, id und curl. Die Attrappen protokollieren
# ihre Aufrufe und merken sich Zustand (installierte Pakete, ufw-Regeln, laufender Edge).
# Geprüft werden: Rollen (ufw, Bindung, dev.-Präfix), DNS-Wahl (Caddyfile, API-Aufrufe,
# acme-dns-CNAME), Idempotenz, Trockenlauf ohne Änderung, Aussperrschutz für SSH, Fehlerausgänge.
# Die edge-site-Fälle mit DNS-API brauchen jq (auf dem Server installiert es setup-server.sh);
# ohne jq werden sie übersprungen — die CI führt sie auf Ubuntu aus.

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
for w in grep sed head tail tr cat mkdir chmod cp rm mv touch stat mktemp dirname env wc find awk readlink ln install sort cut basename printf jq; do
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
stub "$S" systemctl 'echo "systemctl $*" >> "$ZUSTAND/log"'
stub "$S" sysctl 'echo "sysctl $*" >> "$ZUSTAND/log"'
stub "$S" id 'echo 0'
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
out=""; url=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; case "$a" in http*) url="$a";; esac; prev="$a"; done
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

neue_welt() { # neue_welt <name> — frisches Dateisystem mit Ubuntu 26.04
    local w="$tmp/$1"
    mkdir -p "$w/etc/apt/sources.list.d" "$w/zustand"
    printf 'ID=ubuntu\nVERSION_ID="26.04"\nVERSION_CODENAME=resolute\n' > "$w/etc/os-release"
    printf '%s' "$w"
}
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

# Idempotenz: zweiter Lauf ohne Änderung
: > "$w/zustand/log"
out2="$(TS_IP=100.64.0.5 SSH_CONNECTION="100.64.0.9 5000 100.64.0.5 22" lauf "$w" "$SETUP")"; rc=$?
[ $rc -eq 0 ]; behaupte "Dev: zweiter Lauf (gespeicherte Werte) endet mit 0" $?
printf '%s' "$out2" | grep -q "   mache "; [ $? -ne 0 ]; behaupte "Dev: zweiter Lauf ändert nichts" $?
[ $? -eq 0 ] || printf '%s\n' "$out2" | grep "mache" | sed 's/^/       /'
grep -qE "apt-get install|up -d --build" "$w/zustand/log"; [ $? -ne 0 ]; behaupte "Dev: zweiter Lauf installiert und baut nicht" $?
out3="$(TS_IP=100.64.0.5 lauf "$w" "$SETUP" --check)"; rc=$?
[ $rc -eq 0 ] && printf '%s' "$out3" | grep -q "erfüllt den Standard"; behaupte "Dev: --check endet mit 0" $?

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

# --- Prod mit Cloudflare: öffentliche Ports, alle Adressen
w="$(neue_welt prod)"
out="$(TS_IP=100.64.0.6 SSH_CONNECTION="100.64.0.9 5000 100.64.0.6 22" DNS_API_TOKEN=cf lauf "$w" "$SETUP" --rolle prod --dns cloudflare --email admin@example.at)"; rc=$?
[ $rc -eq 0 ]; behaupte "Prod/Cloudflare: Einrichtung endet mit 0" $?
grep -q "ufw allow 80/tcp" "$w/zustand/log" && grep -q "ufw allow 443/tcp" "$w/zustand/log"; behaupte "Prod: 80/443 öffentlich" $?
grep -q "^BIND_IP=0.0.0.0$" "$w/opt/edge/.env"; behaupte "Prod: Edge ausdrücklich auf allen Adressen (0.0.0.0)" $?
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
fi

echo
if [ "$fehler" -eq 0 ]; then echo "Alle Fälle grün."; else echo "Fehler: $fehler"; exit 1; fi
