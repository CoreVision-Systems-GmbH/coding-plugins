# setup.ps1 — richtet einen Windows-Rechner für Augmented Coding nach dem Firmenstandard ein.
#
# Was es tut, in dieser Reihenfolge — jeder Schritt wird übersprungen, wenn er schon erledigt ist:
#   1. Git for Windows            (winget, Git.Git)        — Claude Code braucht Git Bash
#   2. GitHub CLI                 (winget, GitHub.cli)     — Pull Requests, Repos, Releases
#   3. Claude Code                (nativer Installer von claude.ai, aktualisiert sich selbst)
#   4. Marketplace „corevision“   (CoreVision-Systems-GmbH/coding-plugins, öffentlich)
#   5. Plugin coding-standard     (Scope user)
#   6. Prüfung                    (Fassungen, Plugin geladen)
#
# Aufruf, in einer gewöhnlichen PowerShell (kein Administrator nötig; winget fragt bei Bedarf):
#
#   irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1 | iex
#
# Mit Schaltern (Skript zuerst laden, dann aufrufen):
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1))) -GitHubLogin
#
#   -DryRun        zeigt nur, was zu tun wäre, ändert nichts
#   -GitHubLogin   meldet gh am Ende im Browser an und setzt den Git-Credential-Helper auf gh
#
# Was das Skript NICHT tut: Claude Code anmelden (erster Aufruf von `claude` macht das im
# Browser), Stack-Werkzeuge wie PHP, Node oder Python installieren (die nennt das jeweilige
# Projekt in seiner CLAUDE.md), Rechte auf Firmen-Repositories vergeben (macht CoreVision).

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$GitHubLogin
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Marketplace = 'CoreVision-Systems-GmbH/coding-plugins'
$MarketplaceName = 'corevision'
$Plugin = 'coding-standard@corevision'

function Schritt([string]$Text) { Write-Host ""; Write-Host "== $Text" -ForegroundColor Cyan }
function Ok([string]$Text)      { Write-Host "   ok      $Text" -ForegroundColor Green }
function Tun([string]$Text)     { Write-Host "   mache   $Text" -ForegroundColor Yellow }
function Warnung([string]$Text) { Write-Host "   achtung $Text" -ForegroundColor Magenta }
function Fehler([string]$Text)  { Write-Host "   FEHLER  $Text" -ForegroundColor Red }

function Pfad-Auffrischen {
    # Nach winget-Installationen kennt die laufende Sitzung neue Programme noch nicht.
    $m = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u;$env:USERPROFILE\.local\bin"
}

function Vorhanden([string]$Befehl) {
    return [bool](Get-Command $Befehl -ErrorAction SilentlyContinue)
}

function Fassung([string]$Befehl, [string[]]$Argumente) {
    # $Args wäre die automatische Variable — deshalb $Argumente.
    try {
        $zeilen = (& $Befehl @Argumente 2>&1 | Out-String) -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
        if ($zeilen) { return ([string]$zeilen[0]).Trim() } else { return '' }
    } catch { return '' }
}

function Winget-Installieren([string]$Id, [string]$Name) {
    if (-not (Vorhanden 'winget')) {
        Fehler "winget fehlt. $Name bitte von Hand installieren, dann das Skript erneut starten."
        exit 1
    }
    if ($DryRun) { Tun "würde installieren: $Name (winget $Id)"; return }
    Tun "installiere $Name (winget $Id)"
    winget install --id $Id -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    Pfad-Auffrischen
}

$fehler = 0

Write-Host "Augmented Coding — Einrichtung (CoreVision Systems / PCN GmbH)" -ForegroundColor White
if ($DryRun) { Warnung "Trockenlauf: nichts wird verändert." }
Pfad-Auffrischen

# ---------------------------------------------------------------- 1. Git
Schritt "Git for Windows"
if (Vorhanden 'git') { Ok (Fassung 'git' @('--version')) }
else {
    Winget-Installieren 'Git.Git' 'Git for Windows'
    if (-not $DryRun -and -not (Vorhanden 'git')) { Fehler "git nach der Installation nicht im Pfad — neue PowerShell öffnen und Skript erneut starten."; $fehler++ }
}

# ---------------------------------------------------------------- 2. gh
Schritt "GitHub CLI"
if (Vorhanden 'gh') { Ok (Fassung 'gh' @('--version')) }
else {
    Winget-Installieren 'GitHub.cli' 'GitHub CLI'
    if (-not $DryRun -and -not (Vorhanden 'gh')) { Fehler "gh nach der Installation nicht im Pfad — neue PowerShell öffnen und Skript erneut starten."; $fehler++ }
}

# ---------------------------------------------------------------- 3. Claude Code
Schritt "Claude Code"
if (Vorhanden 'claude') { Ok (Fassung 'claude' @('--version')) }
else {
    if ($DryRun) { Tun "würde installieren: Claude Code (irm https://claude.ai/install.ps1 | iex)" }
    else {
        Tun "installiere Claude Code (nativer Installer, aktualisiert sich selbst)"
        Invoke-Expression (Invoke-RestMethod -Uri 'https://claude.ai/install.ps1')
        Pfad-Auffrischen
        if (-not (Vorhanden 'claude')) { Fehler "claude nach der Installation nicht im Pfad — neue PowerShell öffnen und Skript erneut starten."; $fehler++ }
    }
}

# ---------------------------------------------------------------- 4./5. Marketplace + Plugin
Schritt "Marketplace $MarketplaceName und Plugin $Plugin"
if (-not (Vorhanden 'claude')) {
    if ($DryRun) { Tun "würde hinzufügen: Marketplace $Marketplace, Plugin $Plugin" }
    else { Fehler "ohne claude kein Plugin"; $fehler++ }
}
else {
    $liste = (& claude plugin marketplace list 2>&1 | Out-String)
    if ($liste -match [regex]::Escape($Marketplace)) {
        Ok "Marketplace $MarketplaceName zeigt auf $Marketplace"
        if (-not $DryRun) { & claude plugin marketplace update $MarketplaceName | Out-Host }
    }
    elseif ($liste -match "\b$MarketplaceName\b") {
        Warnung "Marketplace $MarketplaceName zeigt auf eine andere Quelle — stelle auf $Marketplace um"
        if (-not $DryRun) {
            & claude plugin marketplace remove $MarketplaceName | Out-Host
            & claude plugin marketplace add $Marketplace | Out-Host
        }
    }
    else {
        if ($DryRun) { Tun "würde hinzufügen: Marketplace $Marketplace" }
        else { Tun "füge Marketplace $Marketplace hinzu"; & claude plugin marketplace add $Marketplace | Out-Host }
    }

    $plugins = (& claude plugin list 2>&1 | Out-String)
    if ($plugins -match [regex]::Escape($Plugin)) {
        Ok "Plugin $Plugin installiert"
        if (-not $DryRun) { & claude plugin update $Plugin | Out-Host }
    }
    else {
        if ($DryRun) { Tun "würde installieren: Plugin $Plugin (Scope user)" }
        else { Tun "installiere Plugin $Plugin"; & claude plugin install $Plugin --scope user | Out-Host }
    }
}

# ---------------------------------------------------------------- gh-Anmeldung (optional)
Schritt "GitHub-Anmeldung"
if (Vorhanden 'gh') {
    $angemeldet = $false
    try { & gh auth status 2>&1 | Out-Null; $angemeldet = ($LASTEXITCODE -eq 0) } catch {}
    if ($angemeldet) {
        Ok "gh ist angemeldet"
        if (-not $DryRun) { & gh auth setup-git | Out-Null; Ok "Git-Credential-Helper: gh" }
    }
    elseif ($GitHubLogin) {
        if ($DryRun) { Tun "würde anmelden: gh auth login --web" }
        else {
            Tun "melde gh im Browser an"
            & gh auth login --hostname github.com --git-protocol https --web
            & gh auth setup-git | Out-Null
        }
    }
    else {
        Warnung "gh ist nicht angemeldet. Für die Arbeit an Firmen-Repos später: gh auth login --web  (oder Skript mit -GitHubLogin)"
    }
}

# ---------------------------------------------------------------- 6. Prüfung
Schritt "Prüfung"
Pfad-Auffrischen
foreach ($b in @('git', 'gh', 'claude')) {
    if (Vorhanden $b) { Ok "$b — $(Fassung $b @('--version'))" }
    elseif ($DryRun) { Tun "$b fehlt noch (Trockenlauf)" }
    else { Fehler "$b fehlt"; $fehler++ }
}
if (Vorhanden 'claude') {
    $plugins = (& claude plugin list 2>&1 | Out-String)
    if ($plugins -match [regex]::Escape($Plugin)) { Ok "Plugin $Plugin geladen" }
    elseif (-not $DryRun) { Fehler "Plugin $Plugin fehlt"; $fehler++ }
}

Write-Host ""
if ($fehler -gt 0) {
    Fehler "$fehler Punkt(e) offen — siehe oben."
    exit 1
}
Write-Host "Fertig. Nächste Schritte:" -ForegroundColor White
Write-Host "   1. Neue PowerShell öffnen (damit alle Pfade gelten)."
Write-Host "   2. 'claude' starten und im Browser anmelden (Pro-, Max-, Team- oder Console-Konto)."
Write-Host "   3. Ein Projekt klonen: gh repo clone CoreVision-Systems-GmbH/<projekt> ~/Code/<projekt> — dem Ordner vertrauen, der Standard lädt sich selbst."
Write-Host "   Handbuch Augmented Coding: bekommst du als PDF von CoreVision Systems."
