#!/usr/bin/env bash
# setup.sh — richtet einen macOS-, Linux- oder WSL-Rechner für Augmented Coding nach dem
# Firmenstandard der CoreVision Systems GmbH ein. Anleitung: EINRICHTUNG.md im selben Repo.
#
# Aufruf:
#
#   curl -fsSL https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.sh | bash
#   curl -fsSL …/setup.sh | bash -s -- --stack laravel --github-login
#
# Schalter:
#
#   --stack <name>   zusätzlich die Werkzeuge eines Stacks: laravel, fastapi, script, astro,
#                    wordpress oder alle; mehrfach oder mit Komma (--stack laravel,astro).
#                    docker nur im Notfall — Container laufen auf dem Dev-Server
#   --check          installiert nichts, prüft nur; Exit 0 heißt: das Gerät ist fertig
#   --liste          zeigt die Bausteine der gewählten Stacks samt Quelle, prüft nichts
#   --dry-run        zeigt, was zu tun wäre, ändert nichts
#   --github-login   meldet gh im Browser an und setzt den Git-Credential-Helper auf gh
#
# Was es tut — jeder Schritt wird übersprungen, wenn er schon erledigt ist:
#   Grundausstattung: git, GitHub CLI, Claude Code, KeePassXC, die Ordner ~/Code und ~/Tresor,
#   Marketplace „corevision“ und Plugin coding-standard mit automatischer Aktualisierung.
#   Auf dem Arbeitsplatz dazu: Tailscale, VS Code mit Remote-SSH und ein SSH-Schlüssel — damit
#   arbeitest du auf dem Dev-Server. Auf dem Dev-Server selbst (setup-server.sh) entfallen sie.
#   Je Stack: PHP 8.4 mit intl, Composer, Laravel-Installer, Node 24, Python 3.12, pipx mit ruff
#   und pytest, shellcheck, PowerShell mit PSScriptAnalyzer; Docker nur mit --stack docker.
#   Quellen: Homebrew auf macOS; apt auf Debian/Ubuntu mit den offiziellen Repos von
#   GitHub CLI, NodeSource, Docker und Microsoft. Andere Linux-Systeme: von Hand.
#
# Was es NICHT tut: Anmeldungen (claude, Docker; gh nur mit --github-login), Git-Identität
# setzen, die Tresor-Datei beschaffen, Rechte auf Firmen-Repos vergeben — das steht am Ende
# als Handgriff. Es löscht nichts; ~/.claude/settings.json wird vor einer Änderung als
# settings.json.bak-setup gesichert, PATH-Zeilen kommen ans Ende von ~/.zshrc bzw. ~/.bashrc.
#
# Rückweg: claude plugin uninstall coding-standard@corevision, claude plugin marketplace
# remove corevision, Werkzeuge mit brew uninstall bzw. apt remove.
# Auf Windows bitte setup.ps1 verwenden (Git Bash ist hier nicht gemeint).

# Der ganze Rest steht in einem { … }-Block: Bash liest ihn vollständig, bevor es ihn ausführt.
# Unter `curl | bash` ist stdin das Skript selbst — ohne den Block könnte ein Kindprozess, der
# stdin liest (Installer, gh), den restlichen Skripttext verschlucken.
{
set -euo pipefail

MARKETPLACE="CoreVision-Systems-GmbH/coding-plugins"
MARKETPLACE_NAME="corevision"
PLUGIN="coding-standard@corevision"
STACKS="laravel fastapi script astro wordpress"
# Reihenfolge zählt: PHP vor Composer vor dem Laravel-Installer, Python vor pipx.
REIHENFOLGE="php composer laravel node docker python pipx shellcheck powershell"
CODE_DIR="$HOME/Code"
TRESOR_DIR="$HOME/Tresor"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

hilfe() {
    # Unter `curl | bash` gibt es keine Datei, aus der sich der Kopf lesen ließe.
    if [ -f "$0" ] && [ "${0##*/}" = setup.sh ]; then sed -n '2,/^# Der ganze Rest/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    else printf 'Schalter: --stack <name>, --check, --liste, --dry-run, --github-login\nAnleitung: https://github.com/CoreVision-Systems-GmbH/coding-plugins/blob/main/EINRICHTUNG.md\n'; fi
}

trocken=0; github_login=0; nur_pruefen=0; nur_liste=0; gewaehlt=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)      trocken=1 ;;
        --github-login) github_login=1 ;;
        --check)        nur_pruefen=1 ;;
        --liste)        nur_liste=1 ;;
        --stack)        [ $# -ge 2 ] || { printf 'Nach --stack fehlt der Name (siehe --help)\n' >&2; exit 1; }
                        gewaehlt="$gewaehlt ${2//,/ }"; shift ;;
        --stack=*)      v="${1#--stack=}"; gewaehlt="$gewaehlt ${v//,/ }" ;;
        --help|-h)      hilfe; exit 0 ;;
        *) printf 'Unbekannte Option: %s (siehe --help)\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

stacks=""
for s in $gewaehlt; do
    if [ "$s" = alle ]; then stacks="$stacks $STACKS"; continue; fi
    if [ "$s" = docker ]; then stacks="$stacks docker"; continue; fi
    case " $STACKS " in
        *" $s "*) stacks="$stacks $s" ;;
        *) printf 'Unbekannter Stack: %s — erlaubt: %s, alle, docker\n' "$s" "${STACKS// /, }" >&2; exit 1 ;;
    esac
done

stack_bausteine() {
    case "$1" in
        laravel)   echo "php composer laravel node" ;;
        wordpress) echo "php composer" ;;
        astro)     echo "node" ;;
        fastapi)   echo "python" ;;
        docker)    echo "docker" ;;
        script)    echo "shellcheck python pipx powershell" ;;
    esac
}
alle_b=""
for s in $stacks; do alle_b="$alle_b $(stack_bausteine "$s")"; done
bausteine=""
for b in $REIHENFOLGE; do case " $alle_b " in *" $b "*) bausteine="$bausteine $b" ;; esac; done

schritt()  { printf '\n== %s\n' "$1"; }
ok()       { printf '   ok      %s\n' "$1"; }
tun()      { printf '   mache   %s\n' "$1"; }
warnung()  { printf '   achtung %s\n' "$1"; }
fehler()   { printf '   FEHLER  %s\n' "$1"; }
vorhanden(){ command -v "$1" >/dev/null 2>&1; }
terminal_da() { ( exec </dev/tty ) 2>/dev/null; }   # öffnen können, nicht nur lesen dürfen
fassung()  { "$1" --version 2>/dev/null | head -1 || true; }
nummer()   { grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true; }

befunde=0
handgriffe=""
befund()   { printf '   FEHLT   %s\n' "$1"; befunde=$((befunde + 1)); }
# Ein Handgriff ist kein Fehler des Laufs, sondern ein Schritt, den nur ein Mensch tun kann.
# Bei --check zählt er als Befund: Das Gerät ist dann noch nicht fertig.
handgriff() {
    if [ $nur_pruefen -eq 1 ]; then befund "$1"; return 0; fi
    printf '   HAND    %s\n' "$1"; handgriffe="$handgriffe
   - $1"
}
# Im Trockenlauf fehlt, was erst der Lauf installieren würde — das ist kein Befund.
fehlt() { if [ $trocken -eq 1 ]; then tun "$1 fehlt noch (Trockenlauf)"; else befund "$1"; fi; }

fassung_ge() {
    # fassung_ge <ist> <soll> — Erfolg, wenn ist >= soll (Vergleich der ersten drei Zahlen).
    local ist="$1" soll="$2" i a b
    local -a A B
    IFS=. read -r -a A <<<"$ist"; IFS=. read -r -a B <<<"$soll"
    for i in 0 1 2; do
        a="${A[$i]:-0}"; b="${B[$i]:-0}"; a="${a//[!0-9]/}"; b="${b//[!0-9]/}"
        a="${a:-0}"; b="${b:-0}"
        if [ "$a" -gt "$b" ]; then return 0; fi
        if [ "$a" -lt "$b" ]; then return 1; fi
    done
    return 0
}

system="${SETUP_SYSTEM:-}"   # SETUP_SYSTEM setzen nur die Tests
if [ -z "$system" ]; then
    case "$(uname -s)" in
        Darwin) system=mac ;;
        Linux)  system=linux ;;
        MINGW*|MSYS*|CYGWIN*) system=windows ;;
        *) system=unbekannt ;;
    esac
fi
if [ "$system" = windows ]; then fehler "Windows erkannt — bitte setup.ps1 in der PowerShell verwenden."; exit 1; fi
wsl=0
if [ "$system" = linux ] && grep -qi microsoft /proc/version 2>/dev/null; then wsl=1; fi
# Auf dem Dev-Server (setup-server.sh) kommen Tailscale und Docker von dort; VS Code und der
# SSH-Schlüssel gehören auf den Arbeitsplatz, von dem aus man sich verbindet.
arbeitsplatz=1
if [ -f "${SERVER_KONF:-/etc/corevision/server.env}" ]; then arbeitsplatz=0; fi

quelle() {
    case "$system:$1" in
        mac:php)          echo "brew install php@8.4 (mit intl), brew link --force php@8.4" ;;
        mac:composer)     echo "brew install composer" ;;
        *:laravel)        echo "composer global require laravel/installer" ;;
        mac:node)         echo "brew install node@24, brew link --force node@24" ;;
        mac:docker)       echo "brew install --cask docker-desktop" ;;
        mac:python)       echo "brew install python@3.12 (Befehl python über libexec/bin)" ;;
        mac:pipx)         echo "brew install pipx; pipx install ruff; pipx install pytest" ;;
        mac:shellcheck)   echo "brew install shellcheck" ;;
        mac:powershell)   echo "brew install powershell; Install-Module PSScriptAnalyzer -Scope CurrentUser" ;;
        linux:php)        echo "apt php8.4-cli php8.4-intl und Erweiterungen (Ubuntu ohne 8.4: ppa:ondrej/php)" ;;
        linux:composer)   echo "getcomposer.org/installer mit Prüfsumme nach ~/.local/bin/composer" ;;
        linux:node)       echo "NodeSource deb.nodesource.com/setup_24.x, apt nodejs" ;;
        linux:docker)     if [ $wsl -eq 1 ]; then echo "Docker Desktop unter Windows mit WSL-Integration (von Hand)"
                          else echo "get.docker.com (offizielles Docker-Skript), Gruppe docker"; fi ;;
        linux:python)     echo "apt python3 python3-venv python3-pip python-is-python3" ;;
        linux:pipx)       echo "apt pipx; pipx install ruff; pipx install pytest" ;;
        linux:shellcheck) echo "apt shellcheck" ;;
        linux:powershell) echo "packages.microsoft.com (powershell); Install-Module PSScriptAnalyzer -Scope CurrentUser" ;;
        *)                echo "nicht automatisch — siehe EINRICHTUNG.md" ;;
    esac
}

if [ $nur_liste -eq 1 ]; then
    printf 'Grundausstattung: git gh claude keepassxc ordner plugin%s\n' "$([ $arbeitsplatz -eq 1 ] && echo ' tailscale vscode remotessh sshkey')"
    for b in $bausteine; do printf '%-11s %s\n' "$b" "$(quelle "$b")"; done
    exit 0
fi

# ---------------------------------------------------------------- Installationshelfer
apt_aktualisiert=0
apt_update_einmal() { if [ $apt_aktualisiert -eq 0 ]; then sudo apt-get update -qq; apt_aktualisiert=1; fi; }
apt_rein() { apt_update_einmal; sudo apt-get install -y -qq "$@"; }

profil_pfad() {
    # Neue Werkzeugpfade gelten sofort in diesem Lauf und dauerhaft über die Shell-Startdatei.
    local dir="$1" rc
    [ -n "$dir" ] || return 0
    case "${SHELL:-}" in */zsh) rc="$HOME/.zshrc" ;; *) rc="$HOME/.bashrc" ;; esac
    export PATH="$dir:$PATH"
    if grep -qsF "$dir" "$rc"; then return 0; fi
    printf '\n# Augmented Coding (setup.sh)\nexport PATH="%s:$PATH"\n' "$dir" >> "$rc"
    tun "PATH-Eintrag in $rc: $dir"
}

gh_repo_einrichten() {
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    apt_aktualisiert=0
}

php_quelle_pruefen() {
    apt_update_einmal
    if LC_ALL=C apt-cache policy php8.4-cli 2>/dev/null | grep -q 'Candidate: [0-9]'; then return 0; fi
    if grep -qi '^ID=ubuntu' /etc/os-release 2>/dev/null; then
        apt_rein software-properties-common
        sudo add-apt-repository -y ppa:ondrej/php
        apt_aktualisiert=0
    else
        fehler "PHP 8.4 fehlt in den Paketquellen — siehe EINRICHTUNG.md (packages.sury.org)"; return 1
    fi
}

composer_installieren() {
    # Offizieller Weg von getcomposer.org: Installer laden, Prüfsumme vergleichen, ausführen.
    local tmp erwartet ist
    tmp="$(mktemp -d)"
    erwartet="$(curl -fsSL https://composer.github.io/installer.sig)"
    curl -fsSL https://getcomposer.org/installer -o "$tmp/installer.php"
    ist="$(php -r "echo hash_file('sha384', '$tmp/installer.php');")"
    if [ "$ist" != "$erwartet" ]; then fehler "Composer-Installer: Prüfsumme stimmt nicht"; rm -rf "$tmp"; return 1; fi
    mkdir -p "$HOME/.local/bin"
    php "$tmp/installer.php" --quiet --install-dir="$HOME/.local/bin" --filename=composer
    rm -rf "$tmp"
}

docker_linux() {
    if [ $wsl -eq 1 ]; then
        handgriff "Docker unter WSL: Docker Desktop in Windows installieren (setup.ps1 -Stack …) und die WSL-Integration einschalten"
        return 0
    fi
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "${USER:-$(id -un)}"
    handgriff "Docker: einmal ab- und wieder anmelden, damit die Gruppe docker gilt"
}

powershell_linux() {
    local id ver tmp
    id="$(. /etc/os-release && echo "$ID")"; ver="$(. /etc/os-release && echo "$VERSION_ID")"
    tmp="$(mktemp -d)"
    if ! curl -fsSL "https://packages.microsoft.com/config/$id/$ver/packages-microsoft-prod.deb" -o "$tmp/ms.deb"; then
        fehler "PowerShell: kein Microsoft-Paket für $id $ver — siehe EINRICHTUNG.md"; rm -rf "$tmp"; return 1
    fi
    sudo dpkg -i "$tmp/ms.deb"; rm -rf "$tmp"
    apt_aktualisiert=0; apt_rein powershell
}

psa_da() { vorhanden pwsh && pwsh -NoProfile -Command 'if (Get-Module -ListAvailable PSScriptAnalyzer) { exit 0 } else { exit 1 }' >/dev/null 2>&1; }
psa_installieren() {
    pwsh -NoProfile -Command 'Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer -Scope CurrentUser -Force'
}

pipx_werkzeuge() {
    local w
    for w in ruff pytest; do vorhanden "$w" || pipx install "$w"; done
    pipx ensurepath >/dev/null 2>&1 || true
    export PATH="$HOME/.local/bin:$PATH"
}

python_ok() {
    local v
    vorhanden python || return 1
    v="$(python -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || true)"
    [ -n "$v" ] && fassung_ge "$v" 3.12
}

schluessel_erzeugen() {
    # Ein Schlüssel je Gerät; die Passphrase fragt ssh-keygen selbst ab (Terminal nötig).
    if ! terminal_da; then handgriff "SSH-Schlüssel erzeugen: ssh-keygen -t ed25519"; return 0; fi
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$(git config --global user.email 2>/dev/null || echo "$USER@$(hostname)")" -f "$HOME/.ssh/id_ed25519" </dev/tty
    handgriff "Öffentlichen Schlüssel (~/.ssh/id_ed25519.pub) beim Dev-Server hinterlegen lassen bzw. ssh-copy-id <name>@<dev-server>"
}

ist_da() {
    case "$1" in
        keepassxc)  vorhanden keepassxc-cli || vorhanden keepassxc || [ -d /Applications/KeePassXC.app ] ;;
        tailscale)  vorhanden tailscale || [ -d /Applications/Tailscale.app ] ;;
        vscode)     vorhanden code ;;
        remotessh)  vorhanden code && code --list-extensions 2>/dev/null | grep -qix ms-vscode-remote.remote-ssh ;;
        sshkey)     [ -f "$HOME/.ssh/id_ed25519" ] || [ -f "$HOME/.ssh/id_rsa" ] ;;
        python)     python_ok ;;
        pipx)       vorhanden pipx && vorhanden ruff && vorhanden pytest ;;
        powershell) psa_da ;;
        *)          vorhanden "$1" ;;
    esac
}

installiere() {
    if [ "$system" = linux ] && ! vorhanden apt-get; then
        fehler "$1: automatisch nur auf Debian/Ubuntu (apt) — siehe EINRICHTUNG.md, Weg B"; return 1
    fi
    case "$system:$1" in
        mac:git)          brew install git ;;
        mac:gh)           brew install gh ;;
        mac:keepassxc)    brew install --cask keepassxc ;;
        mac:tailscale)    brew install --cask tailscale-app && handgriff "Tailscale öffnen und anmelden (Menüleiste)" ;;
        mac:vscode)       brew install --cask visual-studio-code ;;
        *:remotessh)      code --install-extension ms-vscode-remote.remote-ssh ;;
        *:sshkey)         schluessel_erzeugen ;;
        mac:php)          brew install php@8.4 && brew link --force --overwrite php@8.4 ;;
        mac:composer)     brew install composer ;;
        *:laravel)        composer global require laravel/installer && profil_pfad "$(composer global config bin-dir --absolute 2>/dev/null)" ;;
        mac:node)         brew install node@24 && brew link --force --overwrite node@24 ;;
        mac:docker)       brew install --cask docker-desktop && handgriff "Docker Desktop einmal öffnen und die Nutzungsbedingungen bestätigen" ;;
        mac:python)       brew install python@3.12 && profil_pfad "$(brew --prefix python@3.12)/libexec/bin" ;;
        mac:pipx)         brew install pipx && pipx_werkzeuge ;;
        mac:shellcheck)   brew install shellcheck ;;
        mac:powershell)   { vorhanden pwsh || brew install powershell; } && psa_installieren ;;
        linux:git)        apt_rein git ;;
        linux:gh)         gh_repo_einrichten && apt_rein gh ;;
        linux:keepassxc)  apt_rein keepassxc ;;
        linux:tailscale)  curl -fsSL https://tailscale.com/install.sh | sh && handgriff "Tailscale anmelden: sudo tailscale up" ;;
        linux:vscode)     if vorhanden snap; then sudo snap install code --classic
                          else fehler "VS Code: https://code.visualstudio.com/docs/setup/linux (Paketquelle von Microsoft)"; return 1; fi ;;
        linux:php)        php_quelle_pruefen && apt_rein php8.4-cli php8.4-intl php8.4-mbstring php8.4-xml php8.4-zip \
                              php8.4-curl php8.4-sqlite3 php8.4-pgsql php8.4-mysql php8.4-gd php8.4-bcmath unzip ;;
        linux:composer)   composer_installieren ;;
        linux:node)       curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && apt_rein nodejs ;;
        linux:docker)     docker_linux ;;
        linux:python)     apt_rein python3 python3-venv python3-pip python-is-python3 ;;
        linux:pipx)       apt_rein pipx && pipx_werkzeuge ;;
        linux:shellcheck) apt_rein shellcheck ;;
        linux:powershell) { vorhanden pwsh || powershell_linux; } && psa_installieren ;;
        *) fehler "$1: auf diesem System nicht automatisch — siehe EINRICHTUNG.md, Weg B"; return 1 ;;
    esac
}

baustein() {
    # baustein <name> <anzeigename> — installiert, was fehlt; Vorhandenes bleibt, wie es ist.
    if ist_da "$1"; then ok "$2 vorhanden"; return 0; fi
    if [ $trocken -eq 1 ]; then tun "würde installieren: $2 — $(quelle "$1")"; return 0; fi
    tun "installiere $2"
    installiere "$1" || { befund "$2 ließ sich nicht installieren (siehe Ausgabe oben)"; return 0; }
}

autoupdate_gesetzt() {
    # An ist sie, wenn settings.json sie verlangt oder Claude Code sie schon übernommen hat
    # (known_marketplaces.json, z. B. aus der settings.json eines Projekts).
    local datei="$CLAUDE_DIR/settings.json" bekannt="$CLAUDE_DIR/plugins/known_marketplaces.json"
    if vorhanden python3; then
        python3 - "$datei" "$bekannt" "$MARKETPLACE_NAME" <<'PY' 2>/dev/null
import json, os, sys
einstellungen, bekannt, name = sys.argv[1:4]
def an(pfad, *weg):
    if not os.path.exists(pfad):
        return False
    with open(pfad, encoding="utf-8") as f:
        d = json.load(f)
    for schluessel in weg:
        d = d.get(schluessel, {}) if isinstance(d, dict) else {}
    return isinstance(d, dict) and d.get("autoUpdate") is True
sys.exit(0 if an(einstellungen, "extraKnownMarketplaces", name) or an(bekannt, name) else 1)
PY
    else
        grep -qs '"autoUpdate": *true' "$datei" "$bekannt"
    fi
}

autoupdate_setzen() {
    # Claude Code übernimmt den Schalter beim nächsten Sessionstart nach known_marketplaces.json.
    # "marketplace add" schreibt den Eintrag neu und verliert ihn — deshalb erst danach setzen.
    local datei="$CLAUDE_DIR/settings.json"
    if autoupdate_gesetzt; then ok "automatische Aktualisierung ist an"; return 0; fi
    if [ $trocken -eq 1 ]; then tun "würde setzen: autoUpdate für $MARKETPLACE_NAME in $datei"; return 0; fi
    if ! vorhanden python3; then
        handgriff "Automatische Aktualisierung: in Claude Code /plugin → Marketplaces → $MARKETPLACE_NAME → Enable auto-update"
        return 0
    fi
    mkdir -p "$CLAUDE_DIR"
    [ -f "$datei" ] && cp "$datei" "$datei.bak-setup"
    python3 - "$datei" "$MARKETPLACE_NAME" "$MARKETPLACE" <<'PY'
import json, os, sys
pfad, name, repo = sys.argv[1:4]
daten = {}
if os.path.exists(pfad):
    with open(pfad, encoding="utf-8") as f:
        daten = json.load(f)
eintrag = daten.setdefault("extraKnownMarketplaces", {}).setdefault(name, {})
eintrag.setdefault("source", {"source": "github", "repo": repo})
eintrag["autoUpdate"] = True
with open(pfad, "w", encoding="utf-8") as f:
    json.dump(daten, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
    ok "automatische Aktualisierung eingeschaltet ($datei, Sicherung: settings.json.bak-setup)"
}

# ---------------------------------------------------------------- Prüfung
pruefe_baustein() {
    local v w
    case "$1" in
        php)
            if ! vorhanden php; then fehlt "PHP"; return 0; fi
            v="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
            if fassung_ge "$v" 8.4; then ok "PHP $v"; else befund "PHP $v — gebraucht wird 8.4 oder neuer"; fi
            if php -m 2>/dev/null | grep -qix intl; then ok "PHP-Erweiterung intl"
            else befund "PHP ohne Erweiterung intl — Filament-Tests enden sonst mit HTTP 500"; fi ;;
        composer)
            if vorhanden composer; then ok "$(composer --version --no-ansi 2>/dev/null | head -1 || true)"; else fehlt "Composer"; fi ;;
        laravel)
            if vorhanden laravel; then ok "Laravel-Installer $(laravel --version 2>/dev/null | nummer)"; else fehlt "Laravel-Installer (laravel)"; fi ;;
        node)
            if ! vorhanden node; then fehlt "Node"; return 0; fi
            v="$(node -v 2>/dev/null | tr -d v || true)"
            if ! fassung_ge "$v" 22.12; then befund "Node $v — gebraucht wird 22.12 oder neuer (Standard: 24)"
            elif [ "${v%%.*}" != 24 ]; then warnung "Node $v — CI und Abbilder laufen auf Node 24"
            else ok "Node $v"; fi ;;
        docker)
            if ! vorhanden docker; then fehlt "Docker"; return 0; fi
            ok "$(docker --version 2>/dev/null || true)"
            if docker compose version >/dev/null 2>&1; then ok "docker compose"; else befund "docker compose (Compose v2) fehlt"; fi
            docker info >/dev/null 2>&1 || handgriff "Docker läuft nicht — Docker Desktop öffnen bzw. den Dienst docker starten" ;;
        python)
            if ! vorhanden python; then fehlt "Python (Befehl python — die Vorlagen rufen python, nicht python3)"; return 0; fi
            v="$(python -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || true)"
            if [ -z "$v" ]; then befund "python startet nicht"
            elif fassung_ge "$v" 3.12; then ok "Python $v"
            else befund "Python $v — gebraucht wird 3.12 oder neuer"; fi ;;
        pipx)
            for w in pipx ruff pytest; do if vorhanden "$w"; then ok "$w"; else fehlt "$w"; fi; done ;;
        shellcheck)
            if vorhanden shellcheck; then ok "shellcheck $(shellcheck --version 2>/dev/null | nummer)"; else fehlt "shellcheck"; fi ;;
        powershell)
            if ! vorhanden pwsh; then fehlt "PowerShell (pwsh)"; return 0; fi
            ok "PowerShell $(pwsh --version 2>/dev/null | nummer)"
            if psa_da; then ok "PSScriptAnalyzer"; else fehlt "PSScriptAnalyzer"; fi ;;
    esac
}

pruefen() {
    schritt "Prüfung"
    local b
    for b in git gh claude; do
        if vorhanden "$b"; then ok "$b — $(fassung "$b")"; else fehlt "$b"; fi
    done
    # KeePassXC gehört auf den Arbeitsplatz: Auf dem Dev-Server liegt kein Tresor.
    if [ $arbeitsplatz -eq 1 ]; then if ist_da keepassxc; then ok "KeePassXC"; else fehlt "KeePassXC"; fi; fi
    if [ $arbeitsplatz -eq 1 ] && [ $wsl -eq 0 ]; then
        if ist_da tailscale; then ok "Tailscale"; else fehlt "Tailscale"; fi
        if ist_da vscode; then ok "VS Code"; else fehlt "VS Code"; fi
        if ist_da remotessh; then ok "VS Code: Remote-SSH"; else fehlt "VS Code: Remote-SSH"; fi
        if ist_da sshkey; then ok "SSH-Schlüssel"; else fehlt "SSH-Schlüssel (ssh-keygen -t ed25519)"; fi
    fi
    for d in "$CODE_DIR" "$TRESOR_DIR"; do
        if [ -d "$d" ]; then ok "Ordner $d"; else fehlt "Ordner $d"; fi
    done
    if vorhanden claude; then
        if claude plugin list 2>&1 | grep -q "$PLUGIN"; then ok "Plugin $PLUGIN geladen"; else fehlt "Plugin $PLUGIN"; fi
        if autoupdate_gesetzt; then ok "automatische Aktualisierung des Standards an"
        elif [ $trocken -eq 0 ]; then handgriff "Automatische Aktualisierung: in Claude Code /plugin → Marketplaces → $MARKETPLACE_NAME → Enable auto-update"; fi
        if claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; then ok "Claude Code angemeldet"
        else handgriff "Claude Code anmelden: claude starten, im Browser anmelden (Pro, Max, Team, Enterprise oder Console)"; fi
    fi
    if vorhanden gh; then
        if gh auth status >/dev/null 2>&1; then ok "gh angemeldet"
        else handgriff "GitHub anmelden: gh auth login --web (oder Skript mit --github-login)"; fi
    fi
    if vorhanden git; then
        if [ -n "$(git config --global user.name 2>/dev/null || true)" ] && [ -n "$(git config --global user.email 2>/dev/null || true)" ]; then
            ok "Git-Identität: $(git config --global user.name) <$(git config --global user.email)>"
        else
            handgriff "Git-Identität setzen: git config --global user.name \"Vorname Nachname\" und git config --global user.email \"du@firma.tld\""
        fi
    fi
    for b in $bausteine; do pruefe_baustein "$b"; done
}

# ---------------------------------------------------------------- Ablauf
printf 'Augmented Coding — Einrichtung (CoreVision Systems GmbH)\n'
[ $trocken -eq 1 ] && warnung "Trockenlauf: nichts wird verändert."
[ -n "$stacks" ] && printf '   Stacks:%s\n' "$stacks"
export PATH="$HOME/.local/bin:$PATH"

if [ $nur_pruefen -eq 0 ]; then
    if [ "$system" = mac ] && ! vorhanden brew; then
        schritt "Homebrew"
        if [ $trocken -eq 1 ]; then tun "würde installieren: Homebrew (https://brew.sh, fragt nach dem Passwort)"
        else
            # Ohne Terminal an stdin (curl | bash) bricht der Homebrew-Installer ohne sudo ab;
            # deshalb bekommt er das Terminal direkt.
            if terminal_da; then
                tun "installiere Homebrew (https://brew.sh — fragt nach deinem Passwort)"
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty \
                    || befund "Homebrew ließ sich nicht installieren — https://brew.sh, dann Skript erneut starten"
            else
                befund "Homebrew fehlt und es gibt kein Terminal für die Passwortabfrage — https://brew.sh von Hand, dann Skript erneut starten"
            fi
            brew_bin="/opt/homebrew/bin/brew"; [ -x "$brew_bin" ] || brew_bin="/usr/local/bin/brew"
            if [ -x "$brew_bin" ]; then
                eval "$("$brew_bin" shellenv)"
                # Homebrew trägt sich nicht selbst ein; auf Apple Silicon fände eine neue Shell brew sonst nicht.
                if ! grep -qsF "brew shellenv" "$HOME/.zprofile"; then
                    printf '\n# Augmented Coding (setup.sh)\neval "$(%s shellenv)"\n' "$brew_bin" >> "$HOME/.zprofile"
                    tun "Homebrew-Eintrag in $HOME/.zprofile"
                fi
            fi
        fi
    fi

    schritt "Grundausstattung"
    baustein git "git"
    baustein gh "GitHub CLI"
    if vorhanden claude; then ok "Claude Code vorhanden"
    elif [ $trocken -eq 1 ]; then tun "würde installieren: Claude Code (curl -fsSL https://claude.ai/install.sh | bash)"
    else
        tun "installiere Claude Code (nativer Installer, aktualisiert sich selbst)"
        curl -fsSL https://claude.ai/install.sh | bash
        export PATH="$HOME/.local/bin:$PATH"
        vorhanden claude || befund "claude nach der Installation nicht im Pfad — neue Shell öffnen und Skript erneut starten"
    fi
    [ $arbeitsplatz -eq 0 ] || baustein keepassxc "KeePassXC"
    if [ $arbeitsplatz -eq 1 ]; then
        # Unter WSL verbinden VS Code, Tailscale und der SSH-Schlüssel von Windows aus (setup.ps1).
        if [ $wsl -eq 1 ]; then ok "Tailscale, VS Code, SSH-Schlüssel: unter WSL die Windows-Seite verwenden (setup.ps1)"
        else
            baustein tailscale "Tailscale"
            baustein vscode "VS Code"; baustein remotessh "VS Code: Remote-SSH"
            baustein sshkey "SSH-Schlüssel"
        fi
    fi

    schritt "Ordner"
    for d in "$CODE_DIR" "$TRESOR_DIR"; do
        if [ -d "$d" ]; then ok "$d"
        elif [ $trocken -eq 1 ]; then tun "würde anlegen: $d"
        else tun "lege $d an"; mkdir -p "$d"; fi
    done
    # Der Tresor-Ordner gehört nur dir.
    [ $trocken -eq 1 ] || [ ! -d "$TRESOR_DIR" ] || chmod 700 "$TRESOR_DIR"

    schritt "Marketplace $MARKETPLACE_NAME und Plugin $PLUGIN"
    if ! vorhanden claude; then
        if [ $trocken -eq 1 ]; then tun "würde hinzufügen: Marketplace $MARKETPLACE, Plugin $PLUGIN, automatische Aktualisierung"
        else befund "ohne claude kein Plugin"; fi
    else
        liste="$(claude plugin marketplace list 2>&1 || true)"
        if printf '%s' "$liste" | grep -q "$MARKETPLACE"; then
            ok "Marketplace $MARKETPLACE_NAME zeigt auf $MARKETPLACE"
            [ $trocken -eq 1 ] || claude plugin marketplace update "$MARKETPLACE_NAME" || true
        elif printf '%s' "$liste" | grep -qw "$MARKETPLACE_NAME"; then
            warnung "Marketplace $MARKETPLACE_NAME zeigt auf eine andere Quelle — stelle auf $MARKETPLACE um"
            if [ $trocken -eq 0 ]; then
                claude plugin marketplace remove "$MARKETPLACE_NAME" || true
                claude plugin marketplace add "$MARKETPLACE"
            fi
        else
            if [ $trocken -eq 1 ]; then tun "würde hinzufügen: Marketplace $MARKETPLACE"; else tun "füge Marketplace $MARKETPLACE hinzu"; claude plugin marketplace add "$MARKETPLACE"; fi
        fi
        plugins="$(claude plugin list 2>&1 || true)"
        if printf '%s' "$plugins" | grep -q "$PLUGIN"; then
            ok "Plugin $PLUGIN installiert"
            [ $trocken -eq 1 ] || claude plugin update "$PLUGIN" || true
        else
            if [ $trocken -eq 1 ]; then tun "würde installieren: Plugin $PLUGIN (Scope user)"; else tun "installiere Plugin $PLUGIN"; claude plugin install "$PLUGIN" --scope user; fi
        fi
        autoupdate_setzen
    fi

    if [ -n "$bausteine" ]; then
        schritt "Werkzeuge der Stacks:$stacks"
        for b in $bausteine; do
            case "$b" in
                php)        baustein php "PHP 8.4" ;;
                composer)   baustein composer "Composer" ;;
                laravel)    baustein laravel "Laravel-Installer" ;;
                node)       baustein node "Node 24" ;;
                docker)     baustein docker "Docker" ;;
                python)     baustein python "Python 3.12" ;;
                pipx)       baustein pipx "pipx, ruff, pytest" ;;
                shellcheck) baustein shellcheck "shellcheck" ;;
                powershell) baustein powershell "PowerShell und PSScriptAnalyzer" ;;
            esac
        done
    fi

    if [ $github_login -eq 1 ] && vorhanden gh && ! gh auth status >/dev/null 2>&1; then
        schritt "GitHub-Anmeldung"
        if [ $trocken -eq 1 ]; then tun "würde anmelden: gh auth login --web"
        elif terminal_da; then tun "melde gh im Browser an"; gh auth login --hostname github.com --git-protocol https --web </dev/tty || true
        else handgriff "GitHub anmelden: gh auth login --web (kein Terminal für die Anmeldung)"; fi
    fi
    if vorhanden gh && gh auth status >/dev/null 2>&1 && [ $trocken -eq 0 ]; then
        gh auth setup-git >/dev/null 2>&1 && ok "Git-Credential-Helper: gh" || true
    fi
fi

pruefen

printf '\n'
if [ $nur_pruefen -eq 1 ]; then
    if [ $befunde -eq 0 ]; then printf 'Fertig: Das Gerät erfüllt den Standard.\n'; exit 0; fi
    fehler "$befunde Punkt(e) offen — siehe oben und EINRICHTUNG.md."
    [ $befunde -gt 99 ] && exit 99
    exit $befunde
fi
if [ $befunde -gt 0 ]; then fehler "$befunde Punkt(e) offen — siehe oben und EINRICHTUNG.md."; exit 1; fi
if [ $trocken -eq 1 ]; then printf 'Trockenlauf beendet — nichts wurde verändert.\n'; exit 0; fi
if [ -n "$handgriffe" ]; then
    printf 'Installiert. Jetzt noch von Hand (Erklärung in EINRICHTUNG.md, „Handgriffe“):%s\n' "$handgriffe"
else
    printf 'Fertig. Nichts mehr von Hand zu tun.\n'
fi
stackliste="$(printf '%s' "${stacks# }" | tr ' ' ',')"
printf 'Danach: neue Shell öffnen, Kontrolle mit  setup.sh --check%s\n' "${stackliste:+ --stack $stackliste}"
printf 'Projekt holen: gh repo clone CoreVision-Systems-GmbH/<projekt> ~/Code/<projekt>\n'
exit 0
}
