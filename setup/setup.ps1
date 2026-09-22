# setup.ps1 — richtet einen Windows-Rechner für Augmented Coding nach dem Firmenstandard der
# CoreVision Systems GmbH ein. Anleitung: EINRICHTUNG.md im selben Repo.
# (UTF-8 ohne BOM: mit BOM scheitert `irm … | iex` am param-Block. Wer die Datei mit
#  Windows PowerShell 5.1 per -File startet, sieht Umlaute verstümmelt — läuft trotzdem.)
#
# Aufruf, in einer gewöhnlichen PowerShell (kein Administrator nötig; winget fragt bei Bedarf):
#
#   irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1 | iex
#
# Mit Schaltern (Skript zuerst laden, dann aufrufen):
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1))) -Stack laravel -GitHubLogin
#
#   -Stack <name>  zusätzlich die Werkzeuge eines Stacks: laravel, fastapi, script, astro,
#                  wordpress oder alle; mehrere mit Komma (-Stack laravel,astro)
#   -Check         installiert nichts, prüft nur; Exit 0 heißt: das Gerät ist fertig
#   -Liste         zeigt die Bausteine der gewählten Stacks samt Quelle, prüft nichts
#   -DryRun        zeigt, was zu tun wäre, ändert nichts
#   -GitHubLogin   meldet gh im Browser an und setzt den Git-Credential-Helper auf gh
#
# Was es tut — jeder Schritt wird übersprungen, wenn er schon erledigt ist:
#   Grundausstattung: Git for Windows (mit Git Bash, die Claude Code braucht), GitHub CLI,
#   Claude Code, KeePassXC, die Ordner ~\Code und ~\Tresor, Marketplace „corevision“ und
#   Plugin coding-standard mit automatischer Aktualisierung.
#   Je Stack: Herd (PHP 8.4 mit intl, Composer, Laravel-Installer), Node LTS, Docker Desktop,
#   Python 3.12, pipx mit ruff und pytest, shellcheck, PSScriptAnalyzer. Quelle ist winget.
#
# Was es NICHT tut: Anmeldungen (claude, Docker; gh nur mit -GitHubLogin), WSL2 einrichten
# (braucht Administrator und Neustart), Herd zum ersten Mal starten, Git-Identität setzen,
# die Tresor-Datei beschaffen, Rechte auf Firmen-Repos vergeben — das steht am Ende als
# Handgriff. Es löscht nichts; ~\.claude\settings.json wird vor einer Änderung als
# settings.json.bak-setup gesichert.
#
# Rückweg: claude plugin uninstall coding-standard@corevision, claude plugin marketplace
# remove corevision, Werkzeuge mit winget uninstall --id <Id>.

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$GitHubLogin,
    [switch]$Check,
    [switch]$Liste,
    [string[]]$Stack = @()
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Marketplace = 'CoreVision-Systems-GmbH/coding-plugins'
$MarketplaceName = 'corevision'
$Plugin = 'coding-standard@corevision'
$Stacks = @('laravel', 'fastapi', 'script', 'astro', 'wordpress')
# Reihenfolge zählt: PHP vor Composer vor dem Laravel-Installer, Python vor pipx.
$Reihenfolge = @('php', 'composer', 'laravel', 'node', 'docker', 'python', 'pipx', 'shellcheck', 'powershell')
$StackBausteine = @{
    laravel   = @('php', 'composer', 'laravel', 'node', 'docker')
    wordpress = @('php', 'composer', 'docker')
    astro     = @('node', 'docker')
    fastapi   = @('python', 'docker')
    script    = @('shellcheck', 'python', 'pipx', 'powershell')
}
$Quelle = @{
    php        = 'winget BeyondCode.Herd (PHP 8.4 mit intl, Composer, Laravel-Installer)'
    composer   = 'kommt mit Herd'
    laravel    = 'kommt mit Herd'
    node       = 'winget OpenJS.NodeJS.LTS'
    docker     = 'winget Docker.DockerDesktop (braucht WSL2)'
    python     = 'winget Python.Python.3.12 (mit PATH-Eintrag)'
    pipx       = 'python -m pip install --user pipx; pipx install ruff; pipx install pytest'
    shellcheck = 'winget koalaman.shellcheck'
    powershell = 'Install-Module PSScriptAnalyzer -Scope CurrentUser'
}
$CodeDir = Join-Path $HOME 'Code'
$TresorDir = Join-Path $HOME 'Tresor'
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$HerdBin = Join-Path $HOME '.config\herd\bin'

# `exit` würde bei `irm | iex` das Fenster schließen; deshalb Exit-Code setzen und zurückkehren.
function Setze-Exitcode([int]$Code) { $global:LASTEXITCODE = $Code }

$gewaehlt = @()
foreach ($eintrag in $Stack) {
    foreach ($s in ($eintrag -split ',')) {
        $s = $s.Trim().ToLower()
        if (-not $s) { continue }
        if ($s -eq 'alle') { $gewaehlt += $Stacks }
        elseif ($Stacks -contains $s) { $gewaehlt += $s }
        else { Write-Host "Unbekannter Stack: $s — erlaubt: $($Stacks -join ', '), alle"; Setze-Exitcode 1; return }
    }
}
$Bausteine = @($Reihenfolge | Where-Object { $b = $_; @($gewaehlt | Where-Object { $StackBausteine[$_] -contains $b }).Count -gt 0 })

if ($Liste) {
    Write-Host 'Grundausstattung: git gh claude keepassxc ordner plugin'
    foreach ($b in $Bausteine) { Write-Host ('{0,-11} {1}' -f $b, $Quelle[$b]) }
    Setze-Exitcode 0
    return
}

function Schritt([string]$Text) { Write-Host ""; Write-Host "== $Text" -ForegroundColor Cyan }
function Ok([string]$Text)      { Write-Host "   ok      $Text" -ForegroundColor Green }
function Tun([string]$Text)     { Write-Host "   mache   $Text" -ForegroundColor Yellow }
function Warnung([string]$Text) { Write-Host "   achtung $Text" -ForegroundColor Magenta }
function Fehler([string]$Text)  { Write-Host "   FEHLER  $Text" -ForegroundColor Red }

$script:befunde = 0
$script:handgriffe = @()
function Befund([string]$Text) { Write-Host "   FEHLT   $Text" -ForegroundColor Red; $script:befunde++ }
# Ein Handgriff ist kein Fehler des Laufs, sondern ein Schritt, den nur ein Mensch tun kann.
# Bei -Check zählt er als Befund: Das Gerät ist dann noch nicht fertig.
function Handgriff([string]$Text) {
    if ($Check) { Befund $Text; return }
    Write-Host "   HAND    $Text" -ForegroundColor Magenta
    $script:handgriffe += $Text
}
# Im Trockenlauf fehlt, was erst der Lauf installieren würde — das ist kein Befund.
function Fehlt([string]$Text) { if ($DryRun) { Tun "$Text fehlt noch (Trockenlauf)" } else { Befund $Text } }

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
    $zeilen = @(((Aufruf $Befehl $Argumente).Text -split '\r?\n') | Where-Object { $_.Trim() -ne '' })
    if ($zeilen.Count -gt 0) { return ([string]$zeilen[0]).Trim() } else { return '' }
}

function Aufruf([string]$Befehl, [string[]]$Argumente) {
    # Windows PowerShell 5.1 macht aus stderr eines nativen Befehls einen Fehler, der unter
    # ErrorActionPreference=Stop abbricht — gh, docker und wsl schreiben aber gewöhnlich dorthin.
    $alt = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $text = (& $Befehl @Argumente 2>&1 | Out-String); $code = $LASTEXITCODE }
    catch { $text = ''; $code = 1 }
    finally { $ErrorActionPreference = $alt }
    return [pscustomobject]@{ Code = $code; Text = $text }
}

function Nummer([string]$Text) {
    if ($Text -match '(\d+\.\d+(\.\d+)?)') { return [version]$Matches[1] } else { return $null }
}

function Winget-Installieren([string]$Id, [string]$Name, [string]$Override = '') {
    if (-not (Vorhanden 'winget')) {
        Befund "winget fehlt (Microsoft Store: „App-Installer“). $Name bitte nach EINRICHTUNG.md, Weg B, installieren."
        return
    }
    Tun "installiere $Name (winget $Id)"
    $argumente = @('install', '--id', $Id, '-e', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($Override) { $argumente += @('--override', $Override) }
    & winget @argumente | Out-Host
    Pfad-Auffrischen
}

function Herd-Installiert { return ((Test-Path (Join-Path $env:ProgramFiles 'Herd\Herd.exe')) -or (Test-Path $HerdBin)) }
function Python-Echt {
    # Der Store-Alias unter WindowsApps heißt auch python, startet aber nur den Microsoft Store.
    $c = Get-Command python -ErrorAction SilentlyContinue
    return ($c -and ($c.Source -notlike '*\WindowsApps\*'))
}
function PSA-Da { return [bool](Get-Module -ListAvailable PSScriptAnalyzer) }
function WSL-Bereit {
    if (-not (Vorhanden 'wsl')) { return $false }
    return ((Aufruf 'wsl.exe' @('--status')).Code -eq 0)
}
function KeePassXC-Da { return ((Test-Path (Join-Path $env:ProgramFiles 'KeePassXC\KeePassXC.exe')) -or (Vorhanden 'keepassxc-cli')) }

function Ist-Da([string]$B) {
    switch ($B) {
        'php'        { return ((Vorhanden 'php') -or (Herd-Installiert)) }
        'composer'   { return ((Vorhanden 'composer') -or (Herd-Installiert)) }
        'laravel'    { return ((Vorhanden 'laravel') -or (Herd-Installiert)) }
        'python'     { return (Python-Echt) }
        'pipx'       { return ((Vorhanden 'ruff') -and (Vorhanden 'pytest')) }
        'powershell' { return (PSA-Da) }
        default      { return (Vorhanden $B) }
    }
}

function Installiere([string]$B) {
    switch ($B) {
        'php' {
            Winget-Installieren 'BeyondCode.Herd' 'Herd (PHP 8.4, Composer, Laravel-Installer)'
            Handgriff 'Herd einmal starten (Startmenü → Herd), damit php, composer und laravel im PATH stehen; danach neue PowerShell'
        }
        'composer' { }  # kommt mit Herd
        'laravel'  { }  # kommt mit Herd
        'node'     { Winget-Installieren 'OpenJS.NodeJS.LTS' 'Node.js LTS' }
        'docker' {
            if (-not (WSL-Bereit)) {
                Handgriff 'WSL2 fehlt: PowerShell als Administrator öffnen, „wsl --install“ ausführen, neu starten, dieses Skript erneut starten'
                return
            }
            Winget-Installieren 'Docker.DockerDesktop' 'Docker Desktop'
            Handgriff 'Docker Desktop einmal öffnen und die Nutzungsbedingungen bestätigen'
        }
        'python' { Winget-Installieren 'Python.Python.3.12' 'Python 3.12' '/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1' }
        'pipx' {
            if (-not (Python-Echt)) { Befund 'pipx braucht python im PATH — erst Python 3.12, neue PowerShell, Skript erneut'; return }
            Tun 'installiere pipx, ruff, pytest'
            & python -m pip install --user --quiet pipx | Out-Host
            & python -m pipx ensurepath | Out-Null
            foreach ($w in @('ruff', 'pytest')) { if (-not (Vorhanden $w)) { & python -m pipx install $w | Out-Host } }
            Pfad-Auffrischen
        }
        'shellcheck' { Winget-Installieren 'koalaman.shellcheck' 'ShellCheck' }
        'powershell' {
            Tun 'installiere PSScriptAnalyzer (Scope CurrentUser)'
            try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null } catch {}
            Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -Repository PSGallery
        }
    }
}

function Baustein([string]$B, [string]$Name) {
    # Installiert, was fehlt; Vorhandenes bleibt, wie es ist.
    if (Ist-Da $B) { Ok "$Name vorhanden"; return }
    if ($DryRun) { Tun "würde installieren: $Name — $($Quelle[$B])"; return }
    try { Installiere $B } catch { Befund "$Name ließ sich nicht installieren: $($_.Exception.Message)" }
}

function Settings-Lesen {
    $datei = Join-Path $ClaudeDir 'settings.json'
    if (-not (Test-Path $datei)) { return $null }
    try { return (Get-Content $datei -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function Feld($Objekt, [string]$Name) {
    # Unter Set-StrictMode (etwa im Profil) bricht der Zugriff auf eine fehlende Eigenschaft ab.
    if ($null -eq $Objekt) { return $null }
    $p = $Objekt.PSObject.Properties[$Name]
    if ($p) { return $p.Value } else { return $null }
}
function AutoUpdate-Gesetzt {
    # An ist sie, wenn settings.json sie verlangt oder Claude Code sie schon übernommen hat
    # (known_marketplaces.json, z. B. aus der settings.json eines Projekts).
    $m = Feld (Feld (Settings-Lesen) 'extraKnownMarketplaces') $MarketplaceName
    if ((Feld $m 'autoUpdate') -eq $true) { return $true }
    $bekannt = Join-Path $ClaudeDir 'plugins\known_marketplaces.json'
    if (-not (Test-Path $bekannt)) { return $false }
    try { $k = Get-Content $bekannt -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $false }
    return ((Feld (Feld $k $MarketplaceName) 'autoUpdate') -eq $true)
}
function AutoUpdate-Setzen {
    # Claude Code übernimmt den Schalter beim nächsten Sessionstart nach known_marketplaces.json.
    # "marketplace add" schreibt den Eintrag neu und verliert ihn — deshalb erst danach setzen.
    $datei = Join-Path $ClaudeDir 'settings.json'
    if (AutoUpdate-Gesetzt) { Ok 'automatische Aktualisierung ist an'; return }
    if ($DryRun) { Tun "würde setzen: autoUpdate für $MarketplaceName in $datei"; return }
    New-Item -ItemType Directory -Force $ClaudeDir | Out-Null
    $s = [pscustomobject]@{}
    if (Test-Path $datei) {
        Copy-Item $datei "$datei.bak-setup" -Force
        $s = Get-Content $datei -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $alle = Feld $s 'extraKnownMarketplaces'
    if ($null -eq $alle) {
        $alle = [pscustomobject]@{}
        $s | Add-Member -NotePropertyName extraKnownMarketplaces -NotePropertyValue $alle -Force
    }
    $eintrag = Feld $alle $MarketplaceName
    if ($null -eq $eintrag) {
        $eintrag = [pscustomobject]@{ source = [pscustomobject]@{ source = 'github'; repo = $Marketplace } }
        $alle | Add-Member -NotePropertyName $MarketplaceName -NotePropertyValue $eintrag -Force
    }
    $eintrag | Add-Member -NotePropertyName autoUpdate -NotePropertyValue $true -Force
    [System.IO.File]::WriteAllText($datei, ($s | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding $false))
    Ok "automatische Aktualisierung eingeschaltet ($datei, Sicherung: settings.json.bak-setup)"
}

function Pruefe-Baustein([string]$B) {
    switch ($B) {
        'php' {
            if (-not (Vorhanden 'php')) {
                if (Herd-Installiert) { Handgriff 'Herd einmal starten, danach neue PowerShell — php ist sonst nicht im PATH' } else { Fehlt 'PHP (Herd)' }
                return
            }
            $v = Nummer (Fassung 'php' @('-r', 'echo PHP_VERSION;'))
            if ($v -and $v -ge [version]'8.4') { Ok "PHP $v" } else { Befund "PHP $v — gebraucht wird 8.4 oder neuer (in Herd: PHP 8.4 wählen)" }
            $module = (Aufruf 'php' @('-m')).Text
            if ($module -match '(?m)^intl\s*$') { Ok 'PHP-Erweiterung intl' }
            else { Befund "PHP ohne intl ($((Get-Command php).Source)) — meist die herd-lite-Fassung; in Herd PHP 8.4 aktivieren, sonst enden Filament-Tests mit HTTP 500" }
        }
        'composer' { if (Vorhanden 'composer') { Ok (Fassung 'composer' @('--version', '--no-ansi')) } elseif (Herd-Installiert) { Handgriff 'composer fehlt im PATH — Herd einmal starten' } else { Fehlt 'Composer' } }
        'laravel'  { if (Vorhanden 'laravel') { Ok "Laravel-Installer $(Nummer (Fassung 'laravel' @('--version')))" } elseif (Herd-Installiert) { Handgriff 'laravel fehlt im PATH — Herd einmal starten' } else { Fehlt 'Laravel-Installer' } }
        'node' {
            if (-not (Vorhanden 'node')) { Fehlt 'Node'; return }
            $v = Nummer (Fassung 'node' @('-v'))
            if (-not $v -or $v -lt [version]'22.12') { Befund "Node $v — gebraucht wird 22.12 oder neuer (Standard: 24)" }
            elseif ($v.Major -ne 24) { Warnung "Node $v — CI und Abbilder laufen auf Node 24" }
            else { Ok "Node $v" }
        }
        'docker' {
            if (-not (Vorhanden 'docker')) {
                if (-not (WSL-Bereit)) { Handgriff 'WSL2 fehlt: PowerShell als Administrator, „wsl --install“, neu starten, Skript erneut' } else { Fehlt 'Docker Desktop' }
                return
            }
            Ok (Fassung 'docker' @('--version'))
            if ((Aufruf 'docker' @('compose', 'version')).Code -eq 0) { Ok 'docker compose' } else { Befund 'docker compose (Compose v2) fehlt' }
            if ((Aufruf 'docker' @('info')).Code -ne 0) { Handgriff 'Docker läuft nicht — Docker Desktop öffnen' }
        }
        'python' {
            $c = Get-Command python -ErrorAction SilentlyContinue
            if (-not $c) { Fehlt 'Python (Befehl python)'; return }
            if ($c.Source -like '*\WindowsApps\*') { Befund 'python zeigt auf den Store-Alias — Einstellungen → Apps → Erweiterte App-Einstellungen → App-Ausführungsaliase: python.exe und python3.exe aus'; return }
            $v = Nummer (Fassung 'python' @('--version'))
            if ($v -and $v -ge [version]'3.12') { Ok "Python $v" } else { Befund "Python $v — gebraucht wird 3.12 oder neuer" }
        }
        'pipx' { foreach ($w in @('ruff', 'pytest')) { if (Vorhanden $w) { Ok $w } else { Fehlt $w } } }
        'shellcheck' { if (Vorhanden 'shellcheck') { Ok "shellcheck $(Nummer (Fassung 'shellcheck' @('--version')))" } else { Fehlt 'shellcheck' } }
        'powershell' { if (PSA-Da) { Ok 'PSScriptAnalyzer' } else { Fehlt 'PSScriptAnalyzer' } }
    }
}

function Pruefen {
    Schritt 'Prüfung'
    Pfad-Auffrischen
    foreach ($b in @('git', 'gh', 'claude')) {
        if (Vorhanden $b) { Ok "$b — $(Fassung $b @('--version'))" } else { Fehlt $b }
    }
    if (KeePassXC-Da) { Ok 'KeePassXC' } else { Fehlt 'KeePassXC' }
    foreach ($d in @($CodeDir, $TresorDir)) { if (Test-Path $d) { Ok "Ordner $d" } else { Fehlt "Ordner $d" } }
    if (Vorhanden 'claude') {
        if ((Aufruf 'claude' @('plugin', 'list')).Text -match [regex]::Escape($Plugin)) { Ok "Plugin $Plugin geladen" } else { Fehlt "Plugin $Plugin" }
        if (AutoUpdate-Gesetzt) { Ok 'automatische Aktualisierung des Standards an' }
        elseif (-not $DryRun) { Handgriff "Automatische Aktualisierung: in Claude Code /plugin → Marketplaces → $MarketplaceName → Enable auto-update" }
        if ((Aufruf 'claude' @('auth', 'status')).Text -match '"loggedIn":\s*true') { Ok 'Claude Code angemeldet' }
        else { Handgriff 'Claude Code anmelden: claude starten, im Browser anmelden (Pro, Max, Team, Enterprise oder Console)' }
    }
    if (Vorhanden 'gh') {
        if ((Aufruf 'gh' @('auth', 'status')).Code -eq 0) { Ok 'gh angemeldet' } else { Handgriff 'GitHub anmelden: gh auth login --web (oder Skript mit -GitHubLogin)' }
    }
    if (Vorhanden 'git') {
        $name = (Aufruf 'git' @('config', '--global', 'user.name')).Text.Trim()
        $mail = (Aufruf 'git' @('config', '--global', 'user.email')).Text.Trim()
        if ($name -and $mail) { Ok "Git-Identität: $name <$mail>" }
        else { Handgriff 'Git-Identität setzen: git config --global user.name "Vorname Nachname" und git config --global user.email "du@firma.tld"' }
    }
    foreach ($b in $Bausteine) { Pruefe-Baustein $b }
}

# ---------------------------------------------------------------- Ablauf
Write-Host 'Augmented Coding — Einrichtung (CoreVision Systems GmbH)' -ForegroundColor White
if ($DryRun) { Warnung 'Trockenlauf: nichts wird verändert.' }
if ($gewaehlt.Count -gt 0) { Write-Host "   Stacks: $(($gewaehlt | Select-Object -Unique) -join ', ')" }
Pfad-Auffrischen

if (-not $Check) {
    Schritt 'Grundausstattung'
    Baustein 'git' 'Git for Windows'
    Baustein 'gh' 'GitHub CLI'
    if (Vorhanden 'claude') { Ok 'Claude Code vorhanden' }
    elseif ($DryRun) { Tun 'würde installieren: Claude Code (irm https://claude.ai/install.ps1 | iex)' }
    else {
        Tun 'installiere Claude Code (nativer Installer, aktualisiert sich selbst)'
        # Eigener Prozess: install.ps1 schaltet Set-StrictMode ein, das hier sonst weiterwirkte.
        $shell = (Get-Process -Id $PID).Path
        & $shell -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex' | Out-Host
        Pfad-Auffrischen
        if (-not (Vorhanden 'claude')) { Befund 'claude nach der Installation nicht im Pfad — neue PowerShell öffnen und Skript erneut starten' }
    }
    if (KeePassXC-Da) { Ok 'KeePassXC vorhanden' }
    elseif ($DryRun) { Tun 'würde installieren: KeePassXC (winget KeePassXCTeam.KeePassXC)' }
    else { Winget-Installieren 'KeePassXCTeam.KeePassXC' 'KeePassXC' }

    Schritt 'Ordner'
    foreach ($d in @($CodeDir, $TresorDir)) {
        if (Test-Path $d) { Ok $d }
        elseif ($DryRun) { Tun "würde anlegen: $d" }
        else { Tun "lege $d an"; New-Item -ItemType Directory -Force $d | Out-Null }
    }

    Schritt "Marketplace $MarketplaceName und Plugin $Plugin"
    if (-not (Vorhanden 'claude')) {
        if ($DryRun) { Tun "würde hinzufügen: Marketplace $Marketplace, Plugin $Plugin, automatische Aktualisierung" }
        else { Befund 'ohne claude kein Plugin' }
    }
    else {
        $marktplaetze = (Aufruf 'claude' @('plugin', 'marketplace', 'list')).Text
        if ($marktplaetze -match [regex]::Escape($Marketplace)) {
            Ok "Marketplace $MarketplaceName zeigt auf $Marketplace"
            if (-not $DryRun) { & claude plugin marketplace update $MarketplaceName | Out-Host }
        }
        elseif ($marktplaetze -match "\b$MarketplaceName\b") {
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

        $plugins = (Aufruf 'claude' @('plugin', 'list')).Text
        if ($plugins -match [regex]::Escape($Plugin)) {
            Ok "Plugin $Plugin installiert"
            if (-not $DryRun) { & claude plugin update $Plugin | Out-Host }
        }
        else {
            if ($DryRun) { Tun "würde installieren: Plugin $Plugin (Scope user)" }
            else { Tun "installiere Plugin $Plugin"; & claude plugin install $Plugin --scope user | Out-Host }
        }
        AutoUpdate-Setzen
    }

    if ($Bausteine.Count -gt 0) {
        Schritt "Werkzeuge der Stacks: $(($gewaehlt | Select-Object -Unique) -join ', ')"
        $namen = @{ php = 'Herd mit PHP 8.4'; composer = 'Composer'; laravel = 'Laravel-Installer'; node = 'Node.js LTS'; docker = 'Docker Desktop'; python = 'Python 3.12'; pipx = 'pipx, ruff, pytest'; shellcheck = 'ShellCheck'; powershell = 'PSScriptAnalyzer' }
        foreach ($b in $Bausteine) { Baustein $b $namen[$b] }
    }

    if (Vorhanden 'gh') {
        $angemeldet = ((Aufruf 'gh' @('auth', 'status')).Code -eq 0)
        if (-not $angemeldet -and $GitHubLogin) {
            Schritt 'GitHub-Anmeldung'
            if ($DryRun) { Tun 'würde anmelden: gh auth login --web' }
            else {
                Tun 'melde gh im Browser an'
                & gh auth login --hostname github.com --git-protocol https --web
                $angemeldet = ((Aufruf 'gh' @('auth', 'status')).Code -eq 0)
            }
        }
        if ($angemeldet -and -not $DryRun) {
            if ((Aufruf 'gh' @('auth', 'setup-git')).Code -eq 0) { Ok 'Git-Credential-Helper: gh' }
            else { Warnung 'gh auth setup-git ist gescheitert — von Hand: gh auth setup-git' }
        }
    }
}

Pruefen

Write-Host ''
if ($Check) {
    if ($script:befunde -eq 0) { Write-Host 'Fertig: Das Gerät erfüllt den Standard.' -ForegroundColor White; Setze-Exitcode 0; return }
    Fehler "$($script:befunde) Punkt(e) offen — siehe oben und EINRICHTUNG.md."
    Setze-Exitcode ([Math]::Min($script:befunde, 99))
    return
}
if ($script:befunde -gt 0) {
    Fehler "$($script:befunde) Punkt(e) offen — siehe oben und EINRICHTUNG.md."
    Setze-Exitcode 1
    return
}
if ($DryRun) { Write-Host 'Trockenlauf beendet — nichts wurde verändert.' -ForegroundColor White; Setze-Exitcode 0; return }
if ($script:handgriffe.Count -gt 0) {
    Write-Host 'Installiert. Jetzt noch von Hand (Erklärung in EINRICHTUNG.md, „Handgriffe“):' -ForegroundColor White
    foreach ($h in $script:handgriffe) { Write-Host "   - $h" }
}
else { Write-Host 'Fertig. Nichts mehr von Hand zu tun.' -ForegroundColor White }
$stackText = if ($gewaehlt.Count -gt 0) { " -Stack $(($gewaehlt | Select-Object -Unique) -join ',')" } else { '' }
Write-Host "Danach: neue PowerShell öffnen, Kontrolle mit dem Skript und -Check$stackText"
Write-Host 'Projekt holen: gh repo clone CoreVision-Systems-GmbH/<projekt> ~/Code/<projekt>'
Setze-Exitcode 0
