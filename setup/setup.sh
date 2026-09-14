#!/usr/bin/env bash
# setup.sh — richtet einen macOS-, Linux- oder WSL-Rechner für Augmented Coding nach dem
# Firmenstandard ein.
#
# Was es tut, in dieser Reihenfolge — jeder Schritt wird übersprungen, wenn er schon erledigt ist:
#   1. git                        (brew auf macOS, apt auf Debian/Ubuntu)
#   2. GitHub CLI gh              (brew bzw. apt)
#   3. Claude Code                (nativer Installer von claude.ai, aktualisiert sich selbst)
#   4. Marketplace „corevision“   (CoreVision-Systems-GmbH/coding-plugins, öffentlich)
#   5. Plugin coding-standard     (Scope user)
#   6. Prüfung                    (Fassungen, Plugin geladen)
#
# Aufruf:
#
#   curl -fsSL https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.sh | bash
#
# Mit Schaltern:
#
#   curl -fsSL …/setup.sh | bash -s -- --github-login
#
#   --dry-run        zeigt nur, was zu tun wäre, ändert nichts
#   --github-login   meldet gh am Ende im Browser an und setzt den Git-Credential-Helper auf gh
#
# Was das Skript NICHT tut: Claude Code anmelden (erster Aufruf von `claude` macht das im
# Browser), Stack-Werkzeuge wie PHP, Node oder Python installieren (nennt das Projekt in
# seiner CLAUDE.md), Rechte auf Firmen-Repositories vergeben (macht CoreVision).
# Auf Windows bitte setup.ps1 verwenden (Git Bash ist hier nicht gemeint).

set -euo pipefail

MARKETPLACE="CoreVision-Systems-GmbH/coding-plugins"
MARKETPLACE_NAME="corevision"
PLUGIN="coding-standard@corevision"

trocken=0
github_login=0
for arg in "$@"; do
    case "$arg" in
        --dry-run)      trocken=1 ;;
        --github-login) github_login=1 ;;
        --help|-h)      sed -n '2,27p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'Unbekannte Option: %s (siehe --help)\n' "$arg" >&2; exit 1 ;;
    esac
done

schritt()  { printf '\n== %s\n' "$1"; }
ok()       { printf '   ok      %s\n' "$1"; }
tun()      { printf '   mache   %s\n' "$1"; }
warnung()  { printf '   achtung %s\n' "$1"; }
fehler()   { printf '   FEHLER  %s\n' "$1"; }
vorhanden(){ command -v "$1" >/dev/null 2>&1; }
fassung()  { "$1" --version 2>/dev/null | head -1; }

fehlerzahl=0
export PATH="$HOME/.local/bin:$PATH"

case "$(uname -s)" in
    Darwin) system=mac ;;
    Linux)  system=linux ;;
    MINGW*|MSYS*|CYGWIN*) fehler "Windows erkannt — bitte setup.ps1 in der PowerShell verwenden."; exit 1 ;;
    *) system=unbekannt ;;
esac

printf 'Augmented Coding — Einrichtung (CoreVision Systems / PCN GmbH)\n'
[ $trocken -eq 1 ] && warnung "Trockenlauf: nichts wird verändert."

paket_installieren() {
    # paket_installieren <paketname> <anzeigename>
    local paket="$1" name="$2"
    if [ $trocken -eq 1 ]; then tun "würde installieren: $name"; return 0; fi
    if [ "$system" = mac ]; then
        if ! vorhanden brew; then fehler "Homebrew fehlt (https://brew.sh) — $name bitte von Hand installieren."; return 1; fi
        tun "installiere $name (brew)"; brew install "$paket"
    elif vorhanden apt-get; then
        tun "installiere $name (apt)"; sudo apt-get update -qq && sudo apt-get install -y -qq "$paket"
    elif vorhanden dnf; then
        tun "installiere $name (dnf)"; sudo dnf install -y "$paket"
    else
        fehler "Kein bekannter Paketmanager — $name bitte von Hand installieren."; return 1
    fi
}

# ---------------------------------------------------------------- 1. git
schritt "git"
if vorhanden git; then ok "$(fassung git)"; else paket_installieren git "git" || fehlerzahl=$((fehlerzahl + 1)); fi

# ---------------------------------------------------------------- 2. gh
schritt "GitHub CLI"
if vorhanden gh; then ok "$(fassung gh)"; else paket_installieren gh "GitHub CLI" || fehlerzahl=$((fehlerzahl + 1)); fi

# ---------------------------------------------------------------- 3. Claude Code
schritt "Claude Code"
if vorhanden claude; then ok "$(fassung claude)"
elif [ $trocken -eq 1 ]; then tun "würde installieren: Claude Code (curl -fsSL https://claude.ai/install.sh | bash)"
else
    tun "installiere Claude Code (nativer Installer, aktualisiert sich selbst)"
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
    vorhanden claude || { fehler "claude nach der Installation nicht im Pfad — neue Shell öffnen und Skript erneut starten."; fehlerzahl=$((fehlerzahl + 1)); }
fi

# ---------------------------------------------------------------- 4./5. Marketplace + Plugin
schritt "Marketplace $MARKETPLACE_NAME und Plugin $PLUGIN"
if ! vorhanden claude; then
    if [ $trocken -eq 1 ]; then tun "würde hinzufügen: Marketplace $MARKETPLACE, Plugin $PLUGIN"; else fehler "ohne claude kein Plugin"; fehlerzahl=$((fehlerzahl + 1)); fi
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
fi

# ---------------------------------------------------------------- gh-Anmeldung (optional)
schritt "GitHub-Anmeldung"
if vorhanden gh; then
    if gh auth status >/dev/null 2>&1; then
        ok "gh ist angemeldet"
        [ $trocken -eq 1 ] || { gh auth setup-git >/dev/null 2>&1 && ok "Git-Credential-Helper: gh"; }
    elif [ $github_login -eq 1 ]; then
        if [ $trocken -eq 1 ]; then tun "würde anmelden: gh auth login --web"; else tun "melde gh im Browser an"; gh auth login --hostname github.com --git-protocol https --web; gh auth setup-git >/dev/null 2>&1 || true; fi
    else
        warnung "gh ist nicht angemeldet. Für die Arbeit an Firmen-Repos später: gh auth login --web  (oder Skript mit --github-login)"
    fi
fi

# ---------------------------------------------------------------- 6. Prüfung
schritt "Prüfung"
for b in git gh claude; do
    if vorhanden "$b"; then ok "$b — $(fassung "$b")"
    elif [ $trocken -eq 1 ]; then tun "$b fehlt noch (Trockenlauf)"
    else fehler "$b fehlt"; fehlerzahl=$((fehlerzahl + 1)); fi
done
if vorhanden claude; then
    if claude plugin list 2>&1 | grep -q "$PLUGIN"; then ok "Plugin $PLUGIN geladen"
    elif [ $trocken -eq 0 ]; then fehler "Plugin $PLUGIN fehlt"; fehlerzahl=$((fehlerzahl + 1)); fi
fi

printf '\n'
if [ $fehlerzahl -gt 0 ]; then fehler "$fehlerzahl Punkt(e) offen — siehe oben."; exit 1; fi
printf 'Fertig. Nächste Schritte:\n'
printf '   1. Neue Shell öffnen (damit alle Pfade gelten).\n'
printf '   2. claude starten und im Browser anmelden (Pro-, Max-, Team- oder Console-Konto).\n'
printf '   3. Ein Projekt klonen: gh repo clone CoreVision-Systems-GmbH/<projekt> ~/Code/<projekt> — dem Ordner vertrauen, der Standard lädt sich selbst.\n'
printf '   Handbuch Augmented Coding: bekommst du als PDF von CoreVision Systems.\n'
