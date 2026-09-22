#!/usr/bin/env bash
# setup-server.sh — richtet einen Ubuntu-LTS-Server als Dev- oder Prod-Server nach dem
# Firmenstandard der CoreVision Systems GmbH ein: Docker mit Compose, Tailscale, Firewall
# und genau einen Edge-Caddy, der HTTP/HTTPS annimmt und an die Anwendungen weiterreicht.
# Zertifikate kommen von Let's Encrypt über ACME DNS-01 — der Server muss dafür aus dem
# Internet nicht erreichbar sein. Anleitung: EINRICHTUNG.md, Teil B (Dev) und C (Prod).
#
# Aufruf, als root, aus dem geklonten Verteil-Repo:
#
#   sudo git clone https://github.com/CoreVision-Systems-GmbH/coding-plugins /opt/corevision/standard
#   sudo /opt/corevision/standard/plugins/coding-standard/server/setup-server.sh \
#        --rolle dev --dns hetzner --email admin@example.com
#
# Schalter:
#
#   --rolle dev|prod        dev: nur im Tailnet erreichbar, Hostnamen bekommen „dev.“ vorangestellt;
#                           prod: öffentlich auf 80/443, SSH nur über Tailscale
#   --dns hetzner|cloudflare|acmedns
#                           hetzner, cloudflare: DNS-Einträge und Zertifikate über die API des
#                           Anbieters (Token wird abgefragt, nie als Argument);
#                           acmedns: für Anbieter ohne API — je Hostname einmal einen CNAME
#                           von Hand setzen, danach erneuert Caddy allein
#   --email <adresse>       Kontakt für Let's Encrypt (Ablaufwarnungen)
#   --acmedns-url <url>     acme-dns-Server (nur mit --dns acmedns). Ohne Angabe der öffentliche
#                           Dienst https://auth.acme-dns.io — laut Projekt nur zum Testen
#   --ip <adresse>          Ziel der A-Records. Vorgabe: dev die Tailscale-IPv4, prod die IPv4
#                           der Standardroute
#   --check                 installiert nichts, prüft nur; Exit 0 heißt: Server ist fertig
#   --dry-run               zeigt, was zu tun wäre, ändert nichts
#
# Was es tut — jeder Schritt wird übersprungen, wenn er schon erledigt ist:
#   Pakete (curl, git, jq, ufw, unattended-upgrades), Docker mit Compose aus dem offiziellen
#   apt-Repo, Tailscale aus dem offiziellen apt-Repo, Firewall (ufw), /etc/corevision/server.env,
#   /opt/edge mit Edge-Caddy (gebaut aus server/edge/Dockerfile), Netz `edge`, die Befehle
#   edge-site und rollout unter /usr/local/bin, sudo-Regel für die Gruppe docker.
#
# Was es NICHT tut: `tailscale up` (Anmeldung im Browser), Benutzer anlegen, Anwendungen
# einrichten (dafür deploy/install.sh bzw. deploy/dev.sh der Anwendung), etwas löschen.
# Rückweg: docker compose -f /opt/edge/compose.yaml down; ufw disable; Pakete mit apt remove.

# Ganzer Rest in einem Block: bash liest ihn vollständig, bevor es ihn ausführt.
{
set -euo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="${SERVER_WURZEL:-}"     # nur Tests setzen das: Wurzel eines Wegwerf-Dateisystems
KONF_DIR="$W/etc/corevision"
KONF="$KONF_DIR/server.env"
EDGE="$W/opt/edge"
BIN="$W/usr/local/bin"

hilfe() { sed -n '2,/^# Ganzer Rest/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

rolle=""; dns=""; email=""; acmedns_url=""; ziel_ip=""; ip_gegeben=0; trocken=0; nur_pruefen=0
while [ $# -gt 0 ]; do
    case "$1" in
        --rolle)       rolle="${2:-}"; shift ;;
        --dns)         dns="${2:-}"; shift ;;
        --email)       email="${2:-}"; shift ;;
        --acmedns-url) acmedns_url="${2:-}"; shift ;;
        --ip)          ziel_ip="${2:-}"; ip_gegeben=1; shift ;;
        --check)       nur_pruefen=1 ;;
        --dry-run)     trocken=1 ;;
        --help|-h)     hilfe; exit 0 ;;
        *) printf 'Unbekannte Option: %s (siehe --help)\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

# Beim zweiten Lauf gelten die gespeicherten Werte, sofern nichts Neues angegeben ist.
if [ -f "$KONF" ]; then
    # shellcheck disable=SC1090
    gespeichert() { sed -n "s/^$1=//p" "$KONF" | head -1; }
    rolle="${rolle:-$(gespeichert ROLLE)}"; dns="${dns:-$(gespeichert DNS)}"
    email="${email:-$(gespeichert ACME_EMAIL)}"; acmedns_url="${acmedns_url:-$(gespeichert ACMEDNS_URL)}"
    ziel_ip="${ziel_ip:-$(gespeichert ZIEL_IP)}"
fi

fehler_arg() { printf '%s (siehe --help)\n' "$1" >&2; exit 1; }
case "$rolle" in dev|prod) ;; *) fehler_arg "--rolle dev oder --rolle prod angeben" ;; esac
case "$dns" in hetzner|cloudflare|acmedns) ;; *) fehler_arg "--dns hetzner, cloudflare oder acmedns angeben" ;; esac
case "$email" in *@*.*) ;; *) fehler_arg "--email mit gültiger Adresse angeben (Kontakt für Let's Encrypt)" ;; esac
if [ "$dns" = acmedns ] && [ -z "$acmedns_url" ]; then acmedns_url="https://auth.acme-dns.io"; fi
if [ -n "$ziel_ip" ] && ! printf '%s' "$ziel_ip" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    fehler_arg "--ip erwartet eine IPv4-Adresse"
fi

schritt()  { printf '\n== %s\n' "$1"; }
ok()       { printf '   ok      %s\n' "$1"; }
tun()      { printf '   mache   %s\n' "$1"; }
warnung()  { printf '   achtung %s\n' "$1"; }
vorhanden(){ command -v "$1" >/dev/null 2>&1; }
befunde=0; handgriffe=""
befund()   { printf '   FEHLT   %s\n' "$1"; befunde=$((befunde + 1)); }
handgriff() {
    if [ $nur_pruefen -eq 1 ]; then befund "$1"; return 0; fi
    printf '   HAND    %s\n' "$1"; handgriffe="$handgriffe
   - $1"
}

# schreibe <datei> <modus> — schreibt stdin nur, wenn sich der Inhalt ändert. Erfolg (0) heißt:
# geändert. So bleibt ein zweiter Lauf ohne Wirkung, und nur echte Änderungen lösen Neustarts aus.
schreibe() {
    local datei="$1" modus="$2" neu
    neu="$(cat)"
    if [ -f "$datei" ] && [ "$(cat "$datei")" = "$neu" ]; then return 1; fi
    if [ $trocken -eq 1 ]; then tun "würde schreiben: $datei"; return 1; fi
    mkdir -p "$(dirname "$datei")"
    ( umask 077; printf '%s\n' "$neu" > "$datei" )
    chmod "$modus" "$datei"
    tun "geschrieben: $datei"
    return 0
}

apt_aktualisiert=0
apt_rein() {
    if [ $trocken -eq 1 ]; then tun "würde installieren: $*"; return 0; fi
    if [ $apt_aktualisiert -eq 0 ]; then DEBIAN_FRONTEND=noninteractive apt-get update -qq; apt_aktualisiert=1; fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
}
paket_da() { dpkg -s "$1" >/dev/null 2>&1; }

os_wert() { sed -n "s/^$1=//p" "$W/etc/os-release" 2>/dev/null | tr -d '"' | head -1 || true; }
tailscale_ip() { tailscale ip -4 2>/dev/null | head -1 || true; }
standard_ip() { ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1 || true; }

# ---------------------------------------------------------------- Voraussetzungen
printf 'Server einrichten — Rolle %s, DNS %s (CoreVision Systems GmbH)\n' "$rolle" "$dns"
[ $trocken -eq 1 ] && warnung "Trockenlauf: nichts wird verändert."

if [ -z "$W" ] && [ "$(id -u)" -ne 0 ]; then
    printf 'Bitte als root starten: sudo %s …\n' "$0" >&2; exit 1
fi
if [ "$(os_wert ID)" != ubuntu ]; then
    printf 'Nur für Ubuntu LTS gebaut (gefunden: %s). Andere Systeme: EINRICHTUNG.md, Teil B von Hand.\n' "$(os_wert ID)" >&2
    exit 1
fi
version="$(os_wert VERSION_ID)"; codename="$(os_wert VERSION_CODENAME)"
case "$version" in
    24.04|26.04) ;;
    *) printf 'Ubuntu %s ist keine unterstützte LTS-Fassung (24.04 oder 26.04).\n' "$version" >&2; exit 1 ;;
esac

if [ $nur_pruefen -eq 0 ]; then
    # ------------------------------------------------------------ Pakete
    schritt "Grundpakete"
    for p in ca-certificates curl git jq ufw unattended-upgrades; do
        if paket_da "$p"; then ok "$p"; else apt_rein "$p"; fi
    done

    # ------------------------------------------------------------ Docker
    schritt "Docker mit Compose (offizielles apt-Repo)"
    if paket_da docker-ce && paket_da docker-compose-plugin; then ok "$(docker --version 2>/dev/null || echo docker-ce)"
    else
        # Offizieller Weg laut docs.docker.com/engine/install/ubuntu — signiertes Repo, kein curl | sh.
        if [ $trocken -eq 0 ]; then
            install -m 0755 -d "$W/etc/apt/keyrings"
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$W/etc/apt/keyrings/docker.asc"
            chmod a+r "$W/etc/apt/keyrings/docker.asc"
            printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
                "$codename" "$(dpkg --print-architecture)" > "$W/etc/apt/sources.list.d/docker.sources"
            apt_aktualisiert=0
        fi
        apt_rein docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        [ $trocken -eq 1 ] || systemctl enable --now docker containerd
    fi

    # ------------------------------------------------------------ Tailscale
    schritt "Tailscale (offizielles apt-Repo)"
    if paket_da tailscale; then ok "tailscale"
    else
        if [ $trocken -eq 0 ]; then
            install -m 0755 -d "$W/usr/share/keyrings"
            curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$codename.noarmor.gpg" -o "$W/usr/share/keyrings/tailscale-archive-keyring.gpg"
            curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/$codename.tailscale-keyring.list" -o "$W/etc/apt/sources.list.d/tailscale.list"
            apt_aktualisiert=0
        fi
        apt_rein tailscale
    fi

    # ------------------------------------------------------------ Kernel
    # Der Edge bindet auf Dev an die Tailscale-IP. Nach einem Neustart startet Docker oft vor
    # Tailscale — ohne diese Einstellung bliebe der Container dann mit „Exited (128)“ liegen.
    schritt "Kernel-Einstellung für die Tailscale-Bindung"
    if printf 'net.ipv4.ip_nonlocal_bind = 1\n' | schreibe "$W/etc/sysctl.d/99-edge-bind.conf" 644; then
        sysctl -q -p "$W/etc/sysctl.d/99-edge-bind.conf" >/dev/null || true
    else ok "net.ipv4.ip_nonlocal_bind = 1"; fi
fi

# Ziel der A-Records und Bindung des Edge
ts_ip="$(tailscale_ip)"
if [ "$rolle" = dev ] && [ $ip_gegeben -eq 0 ] && [ -n "$ts_ip" ]; then
    # Ändert sich die Tailscale-IP (Knoten neu angemeldet), folgen die A-Records ihr.
    ziel_ip="$ts_ip"
elif [ -z "$ziel_ip" ]; then
    if [ "$rolle" = dev ]; then ziel_ip="$ts_ip"; else ziel_ip="$(standard_ip)"; fi
fi
# Prod: ausdrücklich alle Adressen. Dev: nur die Tailscale-IP — nie ein leerer Wert, denn
# compose.yaml verlangt BIND_IP; fehlt Tailscale, bleibt der alte Wert oder der Edge startet nicht.
if [ "$rolle" = prod ]; then bind_ip="0.0.0.0"
elif [ -n "$ts_ip" ]; then bind_ip="$ts_ip"
else bind_ip="$(sed -n 's/^BIND_IP=//p' "$EDGE/.env" 2>/dev/null | head -1 || true)"
    [ "$bind_ip" = "0.0.0.0" ] && bind_ip=""
fi

if [ $nur_pruefen -eq 0 ]; then
    # ------------------------------------------------------------ Firewall
    # Docker umgeht ufw für veröffentlichte Ports. ufw schützt hier SSH und den Rest des
    # Hosts; den Edge schützt auf Dev die Bindung an die Tailscale-IP.
    schritt "Firewall (ufw)"
    # sudo entfernt SSH_CONNECTION aus der Umgebung; `who -m` kennt die Gegenstelle des Terminals.
    gegenstelle="${SSH_CONNECTION%% *}"
    [ -n "$gegenstelle" ] || gegenstelle="$(who -m 2>/dev/null | sed -n 's/.*(\([0-9.]*\)).*/\1/p' | head -1 || true)"
    ssh_ueber_tailnet=0
    # Tailscale vergibt Adressen aus 100.64.0.0/10 (100.64. bis 100.127.).
    case "$gegenstelle" in
        100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) ssh_ueber_tailnet=1 ;;
    esac
    regeln=("default deny incoming" "default allow outgoing" "allow in on tailscale0")
    if [ "$rolle" = prod ]; then regeln+=("allow 80/tcp" "allow 443/tcp"); fi
    if [ -z "$ts_ip" ] || [ $ssh_ueber_tailnet -eq 0 ]; then
        # Nie aussperren: Port 22 schließt nur, wenn diese Sitzung nachweislich über das Tailnet
        # läuft. Unbekannte Gegenstelle (Konsole, sudo ohne Terminal) → offen lassen.
        regeln+=("allow 22/tcp")
        handgriff "SSH ist noch öffentlich offen. Über das Tailnet neu verbinden (ssh <name>@$([ -n "$ts_ip" ] && echo "$ts_ip" || echo '<tailscale-ip>')) und dieses Skript erneut starten — dann bleibt SSH nur im Tailnet"
    elif ufw status 2>/dev/null | grep -qE '^22/tcp +ALLOW'; then
        if [ $trocken -eq 1 ]; then tun "würde öffentliches SSH schließen (ufw delete allow 22/tcp)"
        else ufw --force delete allow 22/tcp >/dev/null; tun "öffentliches SSH geschlossen — SSH nur noch über das Tailnet"; fi
    fi
    for r in "${regeln[@]}"; do
        # shellcheck disable=SC2086
        if [ $trocken -eq 1 ]; then tun "würde setzen: ufw $r"; else ufw $r >/dev/null; fi
    done
    if ufw status 2>/dev/null | grep -q "Status: active"; then ok "ufw aktiv"
    elif [ $trocken -eq 1 ]; then tun "würde einschalten: ufw enable"
    else ufw --force enable >/dev/null; tun "ufw eingeschaltet"; fi

    # ------------------------------------------------------------ Konfiguration
    schritt "Server-Konfiguration"
    printf '# Verwaltet von setup-server.sh — Änderungen über dessen Schalter.\nROLLE=%s\nDNS=%s\nACME_EMAIL=%s\nACMEDNS_URL=%s\nZIEL_IP=%s\nBIND_IP=%s\n' \
        "$rolle" "$dns" "$email" "$acmedns_url" "$ziel_ip" "$bind_ip" | schreibe "$KONF" 644 || ok "$KONF"

    # ------------------------------------------------------------ Edge
    schritt "Edge-Caddy unter /opt/edge"
    neu_bauen=0; neu_laden=0
    schreibe "$EDGE/Dockerfile" 644 < "$HIER/edge/Dockerfile" && neu_bauen=1
    schreibe "$EDGE/compose.yaml" 644 < "$HIER/edge/compose.yaml" && neu_bauen=1

    # Der Token wird nie als Argument übergeben (Prozessliste, Verlauf): Er kommt aus der
    # Umgebung oder wird verdeckt abgefragt und liegt dann nur in /opt/edge/.env (600).
    token="$(sed -n 's/^DNS_API_TOKEN=//p' "$EDGE/.env" 2>/dev/null | head -1 || true)"
    token="${DNS_API_TOKEN:-$token}"
    if [ "$dns" != acmedns ] && [ -z "$token" ] && [ $trocken -eq 0 ]; then
        if ( exec </dev/tty ) 2>/dev/null; then
            printf '   API-Token für %s (Eingabe unsichtbar): ' "$dns" >/dev/tty
            IFS= read -rs token </dev/tty || true
            printf '\n' >/dev/tty
        fi
        [ -n "$token" ] || handgriff "DNS-Token fehlt: Skript erneut starten und den $dns-Token eingeben (Rechte: EINRICHTUNG.md, Teil D)"
    fi
    printf 'DNS_API_TOKEN=%s\nACME_EMAIL=%s\nBIND_IP=%s\n' "$token" "$email" "$bind_ip" | schreibe "$EDGE/.env" 600 && neu_bauen=1

    case "$dns" in
        hetzner)    tls_zeilen='		dns hetzner {env.DNS_API_TOKEN}
		propagation_delay 30s' ;;
        cloudflare) tls_zeilen='		dns cloudflare {env.DNS_API_TOKEN}
		resolvers 1.1.1.1' ;;
        acmedns)    tls_zeilen='' ;;
    esac
    {
        printf '# Verwaltet von setup-server.sh — nicht von Hand ändern.\n'
        printf '# Je Anwendung eine Datei unter sites/, angelegt mit: sudo edge-site add <host> <container>:<port>\n'
        printf '{\n\temail {env.ACME_EMAIL}\n}\n\n'
        if [ -n "$tls_zeilen" ]; then
            printf '# Zertifikate über ACME DNS-01 (%s) — gilt für jede Site, die „import tls_dns“ enthält.\n' "$dns"
            printf '(tls_dns) {\n\ttls {\n%s\n\t}\n}\n\n' "$tls_zeilen"
        fi
        printf 'import sites/*.caddy\n'
    } | schreibe "$EDGE/caddy/Caddyfile" 644 && neu_laden=1
    for d in sites acmedns; do
        if [ ! -d "$EDGE/caddy/$d" ]; then
            if [ $trocken -eq 1 ]; then tun "würde anlegen: $EDGE/caddy/$d"; else mkdir -p "$EDGE/caddy/$d"; fi
        fi
    done
    [ $trocken -eq 1 ] || { [ ! -d "$EDGE/caddy/acmedns" ] || chmod 700 "$EDGE/caddy/acmedns"; }

    if docker network inspect edge >/dev/null 2>&1; then ok "Netz edge"
    elif [ $trocken -eq 1 ]; then tun "würde anlegen: Netz edge"
    else docker network create edge >/dev/null; tun "Netz edge angelegt"; fi

    if [ "$rolle" = dev ] && [ -z "$bind_ip" ]; then
        warnung "Edge wartet auf Tailscale: Auf Dev bindet er nur an die Tailscale-IP (siehe Prüfung)"
    elif [ $trocken -eq 1 ]; then
        tun "würde bauen und starten: docker compose -f $EDGE/compose.yaml up -d --build"
    elif [ $neu_bauen -eq 1 ] || ! docker compose -f "$EDGE/compose.yaml" ps --status running -q caddy 2>/dev/null | grep -q .; then
        tun "baue und starte den Edge (beim ersten Mal einige Minuten)"
        docker compose -f "$EDGE/compose.yaml" up -d --build
    elif [ $neu_laden -eq 1 ]; then
        docker compose -f "$EDGE/compose.yaml" exec -T caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null
        tun "Edge-Konfiguration neu geladen"
    else
        ok "Edge läuft"
    fi

    # ------------------------------------------------------------ Befehle
    schritt "Befehle edge-site und rollout"
    # Der Starter führt Code aus $HIER als root aus (sudo edge-site): Das Verzeichnis muss root
    # gehören und darf für niemanden sonst beschreibbar sein.
    if [ -z "$W" ]; then
        recht="$(stat -c '%U %a' "$HIER" 2>/dev/null || echo '? 777')"
        case "$recht" in
            "root "[0-7][0-5][0-5]) ;;
            *) printf 'FEHLER  %s gehört nicht root oder ist für andere beschreibbar (%s) — als root klonen.\n' "$HIER" "$recht" >&2; exit 1 ;;
        esac
    fi
    # Starter statt Kopie: Die Befehle bleiben im geklonten Standard und kommen mit
    # `git pull` in neuer Fassung, ohne dass dieses Skript erneut laufen muss.
    for b in edge-site rollout; do
        [ -f "$HIER/$b" ] || continue
        printf '#!/usr/bin/env bash\n# Starter, angelegt von setup-server.sh\nexec bash "%s" "$@"\n' "$HIER/$b" \
            | schreibe "$BIN/$b" 755 || ok "$BIN/$b"
    done
    # Wer in der Gruppe docker ist, ist ohnehin root-gleich; die Regel spart nur die Passwortabfrage.
    if printf '%%docker ALL=(root) NOPASSWD: /usr/local/bin/edge-site\n' \
        | schreibe "$W/etc/sudoers.d/corevision-edge" 440; then
        if vorhanden visudo && ! visudo -cf "$W/etc/sudoers.d/corevision-edge" >/dev/null; then
            rm -f "$W/etc/sudoers.d/corevision-edge"; befund "sudo-Regel ungültig — nicht übernommen"
        fi
    else ok "sudo-Regel für edge-site"; fi
fi

# ---------------------------------------------------------------- Prüfung
schritt "Prüfung"
fehlt() { if [ $trocken -eq 1 ]; then tun "$1 fehlt noch (Trockenlauf)"; else befund "$1"; fi; }
if vorhanden docker && docker compose version >/dev/null 2>&1; then ok "$(docker --version) · $(docker compose version --short 2>/dev/null)"
else fehlt "Docker mit Compose"; fi
wartet_auf_tailscale=0
if [ -n "$ts_ip" ]; then ok "Tailscale verbunden ($ts_ip)"
else
    handgriff "Tailscale anmelden: sudo tailscale up  (Link im Browser öffnen), dann dieses Skript erneut starten"
    [ "$rolle" = dev ] && wartet_auf_tailscale=1
fi
if ufw status 2>/dev/null | grep -q "Status: active"; then ok "ufw aktiv"; else fehlt "ufw aktiv"; fi
if [ -f "$KONF" ]; then ok "$KONF (Rolle $rolle, DNS $dns, Ziel-IP ${ziel_ip:-?})"; else fehlt "$KONF"; fi
if [ -z "$ziel_ip" ] && [ $wartet_auf_tailscale -eq 0 ]; then handgriff "Ziel-IP für A-Records unbekannt — mit --ip <adresse> angeben"; fi
if [ "$dns" != acmedns ] && ! grep -qE '^DNS_API_TOKEN=.+' "$EDGE/.env" 2>/dev/null; then
    handgriff "DNS-Token fehlt in $EDGE/.env — Skript erneut starten"
fi
if docker compose -f "$EDGE/compose.yaml" ps --status running -q caddy 2>/dev/null | grep -q .; then
    if docker compose -f "$EDGE/compose.yaml" exec -T caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        ok "Edge läuft, Konfiguration gültig"
    else befund "Edge-Konfiguration ungültig: docker compose -f $EDGE/compose.yaml exec caddy caddy validate --config /etc/caddy/Caddyfile"; fi
elif [ $wartet_auf_tailscale -eq 1 ]; then warnung "Edge startet nach der Tailscale-Anmeldung (Skript erneut starten)"
else fehlt "Edge-Caddy läuft"; fi
if [ -x "$BIN/edge-site" ]; then ok "edge-site"; else fehlt "$BIN/edge-site"; fi
if [ "$dns" = acmedns ]; then
    case "$acmedns_url" in *auth.acme-dns.io*) warnung "acme-dns über den öffentlichen Testdienst — für Produktion einen eigenen acme-dns-Server (EINRICHTUNG.md, Teil D)";; esac
fi

printf '\n'
if [ $nur_pruefen -eq 1 ]; then
    if [ $befunde -eq 0 ]; then printf 'Fertig: Der Server erfüllt den Standard (Rolle %s).\n' "$rolle"; exit 0; fi
    printf 'FEHLER  %s Punkt(e) offen — siehe oben und EINRICHTUNG.md.\n' "$befunde"
    [ $befunde -gt 99 ] && exit 99
    exit $befunde
fi
if [ $befunde -gt 0 ]; then printf 'FEHLER  %s Punkt(e) offen — siehe oben.\n' "$befunde"; exit 1; fi
if [ $trocken -eq 1 ]; then printf 'Trockenlauf beendet — nichts wurde verändert.\n'; exit 0; fi
if [ -n "$handgriffe" ]; then printf 'Eingerichtet. Jetzt noch von Hand:%s\n' "$handgriffe"
else printf 'Fertig. Anwendung anschließen: sudo edge-site add <host> <container>:<port>\n'; fi
exit 0
}
