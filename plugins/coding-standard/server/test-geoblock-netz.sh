#!/usr/bin/env bash
# test-geoblock-netz.sh — prüft geoblock gegen den echten Kernel: Aus einer fremden Quelle sind
# weder ein Port des Hosts noch ein von Docker veröffentlichter Port noch ping erreichbar, aus
# einer erlaubten schon. Der Test stellt die Gefahr her, statt nur die Regeln zu lesen.
#
# Aufruf:   sudo bash plugins/coding-standard/server/test-geoblock-netz.sh
# Ergebnis: Exit 0, wenn alle Fälle grün sind, sonst Exit 1.
# Braucht:  Linux, root, nft, ip, docker, python3, curl, ping, gzip — die CI (tests.yml).
#
# Aufbau: ein Netz-Namespace „geo-client“ hängt über veth am Host und schickt mit zwei Quellen —
# 203.0.113.10 und 2001:db8:a::10 stehen in der Probeliste als AT, 198.51.100.10 und
# 2001:db8:f::10 als US. Ein zweites veth heißt auf dem Host tailscale0 und steht für das Tailnet.
# Ziele: ein Webserver auf dem Host (python3) und ein Container mit veröffentlichtem Port.
# Verändert den Rechner (Namespace, veth, nft-Tabelle, Container) und räumt am Ende auf.
# Netzaufrufe (Docker Hub, api.github.com) sind hier Absicht, abweichend von .claude/rules/tests.md:
# Ob Antworten auf eigene Verbindungen aus dem Ausland durchkommen, belegt nur eine echte.
# Nicht auf einem Server mit echtem Geoblocking starten — der Test bricht dort ab.

# Prüfmuster `[ … ]; behaupte "…" $?`: $? soll das Ergebnis der Bedingung sein (SC2319).
# shellcheck disable=SC2319

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="$HERE/geoblock"
TABELLE=corevision_geoblock
NS=geo-client
# Per Digest wie die Actions per SHA: Der Lauf hat root, ein getauschtes Abbild liefe mit.
BILD=busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e

fehler=0
behaupte() { if [ "$2" -eq 0 ]; then echo "ok     $1"; else echo "FEHLER $1"; fehler=$((fehler + 1)); fi; }

[ "$(id -u)" -eq 0 ] || { echo "FEHLER braucht root (sudo)"; exit 1; }
for w in nft ip docker python3 curl ping gzip; do
    command -v "$w" >/dev/null 2>&1 || { echo "FEHLER Werkzeug fehlt: $w"; exit 1; }
done
if nft list table inet "$TABELLE" >/dev/null 2>&1; then
    echo "FEHLER Auf diesem Rechner ist Geoblocking aktiv — der Test gehört in die CI"; exit 1
fi

tmp="$(mktemp -d)"
W="$tmp/welt"
aufraeumen() {
    nft delete table inet "$TABELLE" 2>/dev/null
    [ -n "${web_pid:-}" ] && kill "$web_pid" 2>/dev/null
    docker rm -f geo-probe >/dev/null 2>&1
    ip netns del "$NS" 2>/dev/null
    ip link del veth-h 2>/dev/null; ip link del tailscale0 2>/dev/null
    ip route del 203.0.113.10/32 2>/dev/null; ip route del 198.51.100.10/32 2>/dev/null
    ip route del 100.100.1.3/32 2>/dev/null
    rm -rf "$tmp"
}
trap aufraeumen EXIT

gb() { SERVER_WURZEL="$W" SSH_CONNECTION="${SSH_CONNECTION:-}" bash "$G" "$@"; }

# --- Probeliste und Konfiguration (wie nach `geoblock einrichten --laender AT,DE`)
mkdir -p "$W/etc/corevision" "$W/var/lib/corevision/geoblock"
printf '%s\n' \
    '0.0.0.0,0.255.255.255,ZZ' \
    '192.0.2.0,192.0.2.255,US' \
    '198.51.100.0,198.51.100.255,US' \
    '203.0.113.0,203.0.113.127,AT' \
    '203.0.113.200,203.0.113.200,DE' \
    '2001:db8:a::,2001:db8:a:ffff:ffff:ffff:ffff:ffff,AT' \
    '2001:db8:f::,2001:db8:f:ffff:ffff:ffff:ffff:ffff,US' | gzip > "$tmp/probe.csv.gz"
printf 'LAENDER=AT,DE\n' > "$W/etc/corevision/geoblock.conf"
: > "$W/etc/corevision/geoblock-ausnahmen"

# --- Netz: Client-Namespace über veth-h, „Tailnet“ über tailscale0
# Manche Runner-Abbilder schalten IPv6 ab; ohne es fielen die IPv6-Fälle aus dem falschen Grund.
sysctl -qw net.ipv6.conf.all.disable_ipv6=0 net.ipv6.conf.default.disable_ipv6=0
ip netns add "$NS"
ip link add veth-h type veth peer name veth-c
ip link add tailscale0 type veth peer name ts-c
ip link set veth-c netns "$NS"; ip link set ts-c netns "$NS"
ip addr add 192.0.2.1/24 dev veth-h
ip -6 addr add 2001:db8:1::1/64 dev veth-h nodad
ip addr add 100.64.0.1/24 dev tailscale0
ip link set veth-h up; ip link set tailscale0 up
ip netns exec "$NS" sh -eu -c '
    ip link set lo up; ip link set veth-c up; ip link set ts-c up
    ip addr add 192.0.2.2/24 dev veth-c
    ip addr add 203.0.113.10/32 dev veth-c
    ip addr add 198.51.100.10/32 dev veth-c
    ip addr add 100.64.0.2/24 dev ts-c
    ip -6 addr add 2001:db8:1::2/64 dev veth-c nodad
    ip -6 addr add 2001:db8:a::10/128 dev veth-c nodad
    ip -6 addr add 2001:db8:f::10/128 dev veth-c nodad
    ip route add default via 192.0.2.1
    ip -6 route add default via 2001:db8:1::1'
ip route add 203.0.113.10/32 via 192.0.2.2
ip route add 198.51.100.10/32 via 192.0.2.2
ip -6 route add 2001:db8:a::10/128 via 2001:db8:1::2
ip -6 route add 2001:db8:f::10/128 via 2001:db8:1::2

# --- Ziele: Webserver auf dem Host (Port 9000, IPv4 und IPv6), Container mit -p 8080
mkdir -p "$tmp/www"; echo ok > "$tmp/www/index.html"
python3 -m http.server 9000 --bind :: --directory "$tmp/www" >/dev/null 2>&1 &
web_pid=$!
docker run -d --name geo-probe -p 8080:8080 "$BILD" httpd -f -p 8080 -h /etc >/dev/null
for _ in $(seq 1 30); do
    curl -s -o /dev/null --max-time 1 http://127.0.0.1:9000/ && curl -s -o /dev/null --max-time 1 http://127.0.0.1:8080/ && break
    sleep 1
done

# erreicht <quelle> <url> — 0, wenn aus dem Namespace eine HTTP-Antwort kommt (egal welcher Code)
erreicht() {
    local code
    code="$(ip netns exec "$NS" curl -s -o /dev/null -w '%{http_code}' --max-time 3 --interface "$1" "$2" 2>/dev/null)"
    [ -n "$code" ] && [ "$code" != 000 ]
}
pingt() { ip netns exec "$NS" ping -c 1 -W 2 -I "$1" "$2" >/dev/null 2>&1; }

AT4=203.0.113.10; US4=198.51.100.10; AT6=2001:db8:a::10; US6=2001:db8:f::10
HOST=http://192.0.2.1:9000/; DOCKER=http://192.0.2.1:8080/; HOST6='http://[2001:db8:1::1]:9000/'

# Gefälschte Tailnet-Quellen über die öffentliche Schnittstelle (IPv4 CGNAT, IPv6 ULA)
ip netns exec "$NS" ip addr add 100.100.1.3/32 dev veth-c; ip route add 100.100.1.3/32 via 192.0.2.2
ip netns exec "$NS" ip -6 addr add fd7a:115c:a1e0::5/128 dev veth-c nodad; ip -6 route add fd7a:115c:a1e0::5/128 via 2001:db8:1::2
TS4=100.100.1.3; TS6=fd7a:115c:a1e0::5

# --- Gegenprobe ohne Sperre: Alle Quellen kommen an — sonst bewiese „gesperrt“ unten nichts.
erreicht $US4 $HOST && erreicht $US4 $DOCKER && erreicht $US6 "$HOST6" && erreicht $AT4 $HOST     && erreicht $TS4 $HOST && erreicht $TS6 "$HOST6" && pingt $US4 192.0.2.1 && pingt $US6 2001:db8:1::1
behaupte "ohne Geoblocking: alle Quellen erreichen Host und Container, ping kommt an (Aufbau stimmt)" $?

# --- Geoblocking laden
out="$(gb aktualisieren --datei "$tmp/probe.csv.gz" 2>&1)"; rc=$?
[ $rc -eq 0 ] && nft list table inet "$TABELLE" >/dev/null; behaupte "aktualisieren lädt die Tabelle in den Kernel" $?
[ $rc -eq 0 ] || printf '%s\n' "$out" | sed 's/^/       /'

erreicht $AT4 $HOST; behaupte "AT (IPv4) erreicht einen Port des Hosts" $?
erreicht $AT4 $DOCKER; behaupte "AT (IPv4) erreicht den von Docker veröffentlichten Port" $?
erreicht $AT6 "$HOST6"; behaupte "AT (IPv6) erreicht einen Port des Hosts" $?
pingt $AT4 192.0.2.1; behaupte "AT: ping kommt an" $?
nft get element inet "$TABELLE" erlaubt4 '{ 203.0.113.200 }' >/dev/null 2>&1; behaupte "Einzeladresse (DE) steht im Set" $?
erreicht $US4 $HOST; [ $? -ne 0 ]; behaupte "US (IPv4) erreicht keinen Port des Hosts" $?
erreicht $US4 $DOCKER; [ $? -ne 0 ]; behaupte "US (IPv4) erreicht den Docker-Port nicht — prerouting sieht auch weitergeleitete Pakete" $?
erreicht $US6 "$HOST6"; [ $? -ne 0 ]; behaupte "US (IPv6) erreicht keinen Port des Hosts" $?
pingt $US4 192.0.2.1; [ $? -ne 0 ]; behaupte "US: ping (IPv4) kommt nicht an (kein Protokoll)" $?
pingt $US6 2001:db8:1::1; [ $? -ne 0 ]; behaupte "US: ping (IPv6) kommt nicht an" $?
erreicht 100.64.0.2 http://100.64.0.1:9000/; behaupte "Tailnet (tailscale0) erreicht den Host" $?
erreicht $TS4 $HOST; [ $? -ne 0 ]; behaupte "Tailnet-Adresse (IPv4) über die öffentliche Schnittstelle bleibt gesperrt" $?
erreicht $TS6 "$HOST6"; [ $? -ne 0 ]; behaupte "IPv6-ULA (Tailnet-Netz) über die öffentliche Schnittstelle bleibt gesperrt" $?
curl -s -o /dev/null --max-time 15 https://api.github.com/zen; behaupte "ausgehend: Antworten aus dem Ausland kommen an (established)" $?
docker run --rm "$BILD" nslookup github.com >/dev/null 2>&1; behaupte "ausgehend aus einem Container: DNS-Antworten kommen an" $?

# --- Idempotent: zweimal laden, eine Tabelle
gb aktualisieren --datei "$tmp/probe.csv.gz" >/dev/null 2>&1
[ "$(nft list tables | grep -c "inet $TABELLE")" -eq 1 ]; behaupte "zweiter Lauf: genau eine Tabelle" $?

# --- Ausnahmen: Netz erlauben öffnet, entfernen schließt wieder
gb erlauben 198.51.100.0/28 --grund "Probe" >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && erreicht $US4 $DOCKER; behaupte "erlauben 198.51.100.0/28: US-Quelle erreicht den Docker-Port" $?
gb entfernen 198.51.100.0/28 >/dev/null 2>&1
erreicht $US4 $DOCKER; [ $? -ne 0 ]; behaupte "entfernen: US-Quelle wieder gesperrt" $?

# --- Aussperrschutz: eigene SSH-Sitzung aus einer gesperrten Quelle
nft delete table inet "$TABELLE"; rm -f "$W/var/lib/corevision/geoblock/regeln.nft"
SSH_CONNECTION="$US4 50000 192.0.2.1 22" gb aktualisieren --datei "$tmp/probe.csv.gz" >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && ! nft list table inet "$TABELLE" >/dev/null 2>&1; behaupte "Aussperrschutz: Sitzung aus US → zurückgerollt, keine Tabelle" $?
SSH_CONNECTION="$AT4 50000 192.0.2.1 22" gb aktualisieren --datei "$tmp/probe.csv.gz" >/dev/null 2>&1
behaupte "Aussperrschutz: Sitzung aus AT → geladen" $?
SSH_CONNECTION="$US4 50000 192.0.2.1 22" gb aktualisieren --datei "$tmp/probe.csv.gz" --force >/dev/null 2>&1
behaupte "Aussperrschutz: mit --force bewusst übergangen" $?

# --- Kaputte Liste: Die geladene bleibt
# Halbe Datei: Die Probe ist nur gut 120 Bytes groß — eine feste Länge schnitte womöglich nichts ab.
head -c "$(( $(wc -c < "$tmp/probe.csv.gz") / 2 ))" "$tmp/probe.csv.gz" > "$tmp/kaputt.csv.gz"
gzip -t "$tmp/kaputt.csv.gz" 2>/dev/null; [ $? -ne 0 ]; behaupte "Gegenprobe: die abgeschnittene Liste ist wirklich beschädigt" $?
gb aktualisieren --datei "$tmp/kaputt.csv.gz" >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ] && erreicht $AT4 $HOST && ! erreicht $US4 $HOST; behaupte "kaputte Liste: abgelehnt, die geladene Sperre gilt weiter" $?

# --- Start ohne Liste: fail-closed, Tailnet bleibt offen
rm -f "$W/var/lib/corevision/geoblock/regeln.nft"
gb laden >/dev/null 2>&1; rc=$?
[ $rc -ne 0 ]; behaupte "laden ohne Liste endet ≠ 0" $?
erreicht $AT4 $HOST; [ $? -ne 0 ]; behaupte "laden ohne Liste: auch AT gesperrt (fail-closed)" $?
erreicht 100.64.0.2 http://100.64.0.1:9000/; behaupte "laden ohne Liste: Tailnet bleibt offen" $?

echo
if [ "$fehler" -eq 0 ]; then echo "Alle Fälle grün."; exit 0; fi
echo "$fehler Fall/Fälle rot."; exit 1
