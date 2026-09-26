# Einrichtung — Arbeitsplatz, Dev-Server und Prod-Server

Dieses Kochbuch führt von frischen Geräten zu einer Arbeitsumgebung, in der Claude Code nach dem
Firmenstandard der CoreVision Systems GmbH arbeitet. Du brauchst dafür nichts außer diesem
Repository — keinen Zugang zu internen Laufwerken und keine Vorlage von einem anderen Rechner.

## Überblick

```
Arbeitsplatz (Laptop)        VS Code mit Remote-SSH, Tailscale, SSH-Schlüssel, Claude Code
        │  SSH über das Tailnet
Dev-Server (Ubuntu LTS)      ~/Code/<projekt> — hier liegt der Code, hier arbeitet Claude Code
        │                    deploy/dev.sh up → https://dev.<domain> (nur im Tailnet)
        │  PR → Merge → Release vX.Y.Z (GitHub)
Prod-Server (Ubuntu LTS)     sudo rollout <app> jetzt | planen "<termin>" → https://<domain>
```

Beide Server sind gleich gebaut: Docker mit Compose und **genau ein Edge-Caddy**, der alle
HTTP-/HTTPS-Anfragen annimmt und nach Hostname an die Anwendungen weiterreicht. Zertifikate
kommen von Let's Encrypt über **ACME DNS-01** — dafür muss ein Server nicht aus dem Internet
erreichbar sein. Der Unterschied: Der Dev-Server ist nur im Tailnet erreichbar und hängt vor
jede Adresse `dev.`; der Prod-Server ist öffentlich und bekommt Fassungen nur auf Auftrag.

| Teil | Für wen | Ergebnis |
|---|---|---|
| **A — Arbeitsplatz** | jede Person, die am Code arbeitet | Laptop mit Verbindung zum Dev-Server |
| **B — Dev-Server** | wer den Dev-Server einrichtet (einmal) | Server mit Edge, Stack-Werkzeugen, Konten der Entwickler |
| **C — Prod-Server** | wer den Prod-Server einrichtet (einmal) | Server mit Edge; Anwendungen per `deploy/install.sh` |
| **D — DNS und Zertifikate** | wer Domains verwaltet | API-Token oder acme-dns, Einträge je Anwendung |
| **E — Rollout** | wer Fassungen auf Prod freigibt | sofort oder zum Termin, mit Rückweg |

---

# Teil A — Arbeitsplatz

Zwei Wege zum selben Ergebnis:

- **Weg A — das Einrichtungsskript.** Ein Befehl installiert alles, was sich ohne Menschen
  installieren lässt, und nennt am Ende die Handgriffe, die nur du tun kannst. 10 bis 30 Minuten.
- **Weg B — von Hand.** Dieselben Schritte einzeln, mit Quelle und Prüfbefehl je Werkzeug.

Beide enden mit derselben Kontrolle: `setup … --check` (A.8). Endet sie mit „Das Gerät erfüllt
den Standard“, bist du fertig.

## A.1 Voraussetzungen

| Was | Warum | Woher |
|---|---|---|
| Windows 10 22H2 oder 11, macOS 13 oder neuer, Ubuntu 24.04 oder neuer, Debian 13 | darauf ist das Skript ausgelegt; andere Linux-Systeme über Weg B | — |
| Ein Benutzerkonto mit Recht auf Installationen | Windows: winget fragt per Benutzerkontensteuerung nach. macOS: Administratorkonto (Homebrew fragt nach deinem Passwort). Linux: `sudo` | deine IT |
| GitHub-Konto mit **Zwei-Faktor-Anmeldung** | für die Arbeit an unseren Repositories; zum Installieren des Standards nicht nötig | [github.com/signup](https://github.com/signup), 2FA unter Settings → Password and authentication |
| Claude-Abo mit Claude Code | Pro, Max, Team, Enterprise oder ein Console-Konto (API); der kostenlose Tarif enthält Claude Code nicht | [claude.com/pricing](https://claude.com/pricing) — klären wir mit dir |
| Tailscale-Konto und Freigabe des Dev-Servers | der Dev-Server ist nur über Tailscale erreichbar; jeder Server hat sein eigenes Tailnet und wird dir geteilt (B.2) | Konto legst du an, die Freigabe (Sharing) schickt CoreVision |
| Konto auf dem Dev-Server | dort liegt dein Code | legt CoreVision an, sobald dein öffentlicher SSH-Schlüssel da ist (A.6.5) |
| Einladung in die Organisation `CoreVision-Systems-GmbH` | Lese- und Schreibrecht auf dein Projekt | bekommst du von CoreVision, sobald dein GitHub-Name bekannt ist |
| Deine Tresor-Datei (`.kdbx`) | die Geheimnisse deines Projekts (A.6.4) | bekommst du von CoreVision |

## A.2 Verzeichnisstruktur

Der Standard setzt genau zwei Ordner voraus — auf dem Arbeitsplatz und auf dem Dev-Server.
Das Skript legt sie an.

| Ordner | Windows | macOS / Linux | Zweck |
|---|---|---|---|
| `~/Code` | `C:\Users\<du>\Code` | `/Users/<du>/Code`, `/home/<du>/Code` | **ein Unterordner je Projekt**: `~/Code/<projekt>`. Auf dem Dev-Server liegt dort dein Arbeitsstand; hier klont `gh repo clone` hin, hier legt `/projekt-neu` an. |
| `~/Tresor` | `C:\Users\<du>\Tresor` | `~/Tresor` (Rechte `700`) | deine KeePassXC-Datei `<name>.kdbx`. Nur für dich, nie in einem Repository. |

Dazu kommen Ordner, die die Werkzeuge selbst verwalten — nicht von Hand ändern:

| Ordner | Wer | Inhalt |
|---|---|---|
| `~/.claude/` | Claude Code | `settings.json`, `plugins/` (Marketplace und Plugin-Cache `plugins/cache/corevision/coding-standard/<fassung>/`) |
| `~/.ssh/` | OpenSSH | dein Schlüssel `id_ed25519` für den Dev-Server |
| `~/.local/bin` | Claude Code, pipx, Composer unter Linux | Programme ohne Administrator |
| `~/.config/herd/` | Herd (Windows) | PHP 8.4, Composer, Laravel-Installer |

Warum genau so:

- **`Code` mit großem C.** Unter macOS und Linux sind `Code` und `code` zwei verschiedene Ordner.
- **Nicht in OneDrive, iCloud oder Dropbox.** Synchronisierte Ordner vertragen `.git`,
  `node_modules` und `vendor` schlecht. Gesichert wird Code über GitHub.
- **Nichts sonst ist Pflicht.** Ein Notiz-Vault ist persönlich und optional (`/projekt-neu --vault`).

## A.3 Werkzeuge — was du wirklich brauchst

Gearbeitet wird **auf dem Dev-Server**: Dort liegen Code, Stack-Werkzeuge und Container. Auf dem
Arbeitsplatz genügt die **Grundausstattung**; Stack-Werkzeuge braucht er nur, wenn du auch lokal
prüfen willst, und **Docker nur im Notfall** (etwa ohne Verbindung zum Dev-Server).

**Grundausstattung** (immer): Git (Windows mit Git Bash — die Hooks des Standards sind
bash-Skripte), GitHub CLI `gh`, Claude Code, gitleaks (Geheimnis-Scanner — der pre-commit-Hook
jedes Projekts ruft ihn vor jedem Commit auf), KeePassXC, die Ordner aus A.2, der Marketplace
`corevision` mit dem Plugin `coding-standard` und automatischer Aktualisierung — und für die
Verbindung zum Dev-Server **Tailscale, VS Code mit der Erweiterung Remote-SSH und ein
SSH-Schlüssel**.

**Stack-Werkzeuge** mit `--stack` bzw. `-Stack` — auf dem Dev-Server immer, auf dem Arbeitsplatz
nach Bedarf:

| Baustein | laravel | wordpress | astro | fastapi | script | Fassung |
|---|:-:|:-:|:-:|:-:|:-:|---|
| PHP mit `intl` | ● | ● | | | | 8.4 oder neuer |
| Composer | ● | ● | | | | 2 |
| Laravel-Installer | ● | | | | | aktuell |
| Node.js | ● | | ● | | | 24 (mindestens 22.12) |
| Python | | | | ● | ● | 3.12 oder neuer, Befehl `python` |
| pipx mit ruff und pytest | | | | | ● | aktuell |
| ShellCheck | | | | | ● | aktuell |
| PowerShell mit PSScriptAnalyzer | | | | | ● | 7 bzw. Windows PowerShell 5.1 |
| Docker mit Compose v2 | nur mit `--stack docker` (Notfall); auf den Servern richtet `setup-server.sh` es ein | | | | | aktuell |

Nicht nötig sind: jq, eine lokale Datenbank (jede Anwendung bringt ihre im eigenen Container mit),
wp-cli (liegt im Abbild). FastAPI-Projekte bringen ruff, mypy und pytest über
`requirements-dev.txt` in ihre eigene `.venv` mit.

**Fassungen:** CI und Abbilder laufen auf PHP 8.4, Node 24 und Python 3.12. Installiert wird die
neueste Fassung innerhalb dieser Linie; neuere (Node 26, Python 3.13) funktionieren meist, die
Kontrolle warnt dann.

## A.4 Weg A — das Einrichtungsskript

### A.4.1 Aufruf

**Windows** — eine gewöhnliche PowerShell öffnen (kein Administrator):

```powershell
irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1 | iex
```

Mit Schaltern (Skript laden, dann aufrufen):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1))) -GitHubLogin
```

**macOS, Linux, WSL** — ein Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.sh | bash -s -- --github-login
```

| Schalter (PowerShell / bash) | Wirkung |
|---|---|
| `-Stack <name>` / `--stack <name>` | zusätzlich die Werkzeuge eines Stacks: `laravel`, `fastapi`, `script`, `astro`, `wordpress`, `alle`; `docker` nur im Notfall; mehrere mit Komma |
| `-GitHubLogin` / `--github-login` | meldet `gh` im Browser an und richtet Git so ein, dass es sich über `gh` anmeldet |
| `-DryRun` / `--dry-run` | zeigt nur, was passieren würde; ändert nichts |
| `-Liste` / `--liste` | zeigt die Bausteine der gewählten Stacks samt Quelle |
| `-Check` / `--check` | installiert nichts, prüft nur (A.8) |

Unsicher? Erst mit `-DryRun` bzw. `--dry-run` laufen lassen und lesen, was es vorhat.

### A.4.2 Was das Skript tut

In dieser Reihenfolge; Vorhandenes wird übersprungen — ein zweiter Lauf holt nur Fehlendes nach.

1. **Grundausstattung:** Git, GitHub CLI, Claude Code (nativer Installer, aktualisiert sich
   selbst), gitleaks, KeePassXC; auf dem Arbeitsplatz dazu Tailscale, VS Code, die Erweiterung
   Remote-SSH und ein SSH-Schlüssel (`ssh-keygen -t ed25519`, fragt nach einer Passphrase).
   macOS: vorher Homebrew, falls es fehlt (fragt nach deinem Passwort).
2. **Ordner** `~/Code` und `~/Tresor` (A.2).
3. **Marketplace und Plugin** mit **automatischer Aktualisierung** (A.9) und **Lesesperren für
   Claude-Sessions**: `permissions.deny` in `~/.claude/settings.json` sperrt für die Werkzeuge
   das Lesen von `.env` und ihren Varianten, `~/Tresor`, `~/.ssh`, privaten Schlüsseln und
   Datenbank-Dumps — in jedem Repo, auch ohne erklärten Standard. Vorhandene Einträge bleiben;
   die alte Fassung bleibt als `settings.json.bak-setup`.
4. **Werkzeuge der gewählten Stacks** (A.3), aus diesen Quellen:

   | Baustein | Windows (winget) | macOS (Homebrew) | Ubuntu/Debian (apt) |
   |---|---|---|---|
   | gitleaks | `Gitleaks.Gitleaks` | `gitleaks` | Binary 8.30.1 aus dem GitHub-Release mit Prüfsumme nach `~/.local/bin` (kein apt-Paket) |
   | Tailscale | `Tailscale.Tailscale` | Cask `tailscale-app` | Skript `tailscale.com/install.sh` |
   | VS Code, Remote-SSH | `Microsoft.VisualStudioCode`, dann `code --install-extension ms-vscode-remote.remote-ssh` | Cask `visual-studio-code`, dann dasselbe | `snap install code --classic`, dann dasselbe |
   | PHP, Composer, Laravel-Installer | `BeyondCode.Herd` | `php@8.4`, `composer`, dann `composer global require laravel/installer` | `php8.4-cli php8.4-intl …` (Ubuntu ohne 8.4: PPA `ondrej/php`), Composer von getcomposer.org mit Prüfsumme |
   | Node.js | `OpenJS.NodeJS.LTS` | `node@24` | NodeSource-Repo `setup_24.x`, Paket `nodejs` |
   | Python | `Python.Python.3.12` mit PATH-Eintrag | `python@3.12` | `python3 python3-venv python3-pip python-is-python3` |
   | pipx, ruff, pytest | `python -m pip install --user pipx` | `pipx` | `pipx` |
   | ShellCheck | `koalaman.shellcheck` | `shellcheck` | `shellcheck` |
   | PowerShell, PSScriptAnalyzer | `Install-Module PSScriptAnalyzer -Scope CurrentUser` | `powershell`, dann dasselbe | Microsoft-Repo `packages-microsoft-prod.deb`, dann dasselbe |
   | Docker (Notfall) | `Docker.DockerDesktop` (braucht WSL2) | Cask `docker-desktop` | Skript `get.docker.com`, Gruppe `docker` |

5. **GitHub-Anmeldung**, wenn du `-GitHubLogin`/`--github-login` angegeben hast.
6. **Prüfung** — wie `--check`.

Auf macOS und Linux trägt das Skript neue Programmpfade am Ende von `~/.zshrc` bzw. `~/.bashrc`
ein, gekennzeichnet mit `# Augmented Coding (setup.sh)`.

### A.4.3 Die Ausgabe lesen

| Kennung | Bedeutung |
|---|---|
| `ok` | vorhanden und in Ordnung |
| `mache` | wird gerade installiert oder angelegt |
| `achtung` | kein Fehler, aber bemerkenswert — z. B. Node 26 statt 24 |
| `HAND` | ein Handgriff, den nur du tun kannst — Erklärung in A.6 |
| `FEHLT` / `FEHLER` | etwas fehlt oder ist schiefgegangen; die Zeile sagt, was zu tun ist |

Am Ende steht „Fertig. Nichts mehr von Hand zu tun.“ oder die Liste **„Jetzt noch von Hand“**.
Exit 0, wenn nur Handgriffe offen sind; Exit 1, wenn etwas nicht installiert werden konnte.

### A.4.4 Wann du das Skript erneut startest

- **Nach einem Neustart**, den ein Installer verlangt hat.
- **Nach dem ersten Start von Herd** (Windows) oder in einer neuen Shell, wenn eine Zeile
  „nicht im Pfad“ meldete.
- **Wenn du später einen weiteren Stack brauchst:** mit `--stack <neuer stack>`.

## A.5 Weg B — von Hand

Jede Zeile: Zweck, Quelle, Befehl, Prüfung. Reihenfolge wie im Skript.

### A.5.1 Grundausstattung

**Git** — Versionsverwaltung; unter Windows mit Git Bash. Quelle: [git-scm.com/downloads](https://git-scm.com/downloads).

```
Windows:  winget install --id Git.Git -e
macOS:    xcode-select --install        (oder: brew install git)
Linux:    sudo apt install git
Prüfen:   git --version
```

**GitHub CLI** — Klonen, Pull Requests, Anmeldung für Git.
Quelle: [cli.github.com](https://cli.github.com), Linux: [Anleitung für apt](https://github.com/cli/cli/blob/trunk/docs/install_linux.md).

```
Windows:  winget install --id GitHub.cli -e
macOS:    brew install gh
Linux:    offizielles apt-Repo nach der Anleitung oben, dann sudo apt install gh
Prüfen:   gh --version
```

**Claude Code** — der native Installer aktualisiert sich selbst; Pakete aus winget oder Homebrew
tun das nicht. Quelle: [code.claude.com/docs/en/setup](https://code.claude.com/docs/en/setup).

```
Windows:      irm https://claude.ai/install.ps1 | iex
macOS/Linux:  curl -fsSL https://claude.ai/install.sh | bash
Prüfen:       claude --version
```

**gitleaks** — Geheimnis-Scanner. Der pre-commit-Hook jedes Projekts (`.githooks/pre-commit`)
ruft ihn vor jedem Commit auf, die CI prüft dieselben Regeln (`.gitleaks.toml`) noch einmal.
Fehlt er, warnt der Hook nur. In der CI läuft fest 8.30.1; lokal die aktuelle Fassung
(unter Linux das Binary 8.30.1 mit festgenagelter Prüfsumme), mindestens 8.19 wegen `gitleaks git`.
Quelle: [github.com/gitleaks/gitleaks](https://github.com/gitleaks/gitleaks).

```
Windows:  winget install --id Gitleaks.Gitleaks -e
macOS:    brew install gitleaks
Linux:    von github.com/gitleaks/gitleaks/releases (v8.30.1) gitleaks_8.30.1_linux_x64.tar.gz und
          gitleaks_8.30.1_checksums.txt laden, sha256sum -c --ignore-missing gitleaks_8.30.1_checksums.txt,
          dann das Binary gitleaks aus dem Archiv nach ~/.local/bin (kein apt-Paket)
Prüfen:   gitleaks version   → 8.30.1
```

**KeePassXC** — Tresor für Geheimnisse (A.6.4). Quelle: [keepassxc.org/download](https://keepassxc.org/download/).

```
Windows:  winget install --id KeePassXCTeam.KeePassXC -e
macOS:    brew install --cask keepassxc
Linux:    sudo apt install keepassxc
```

**Tailscale** — privates Netz zum Dev-Server. Quelle: [tailscale.com/download](https://tailscale.com/download).

```
Windows:  winget install --id Tailscale.Tailscale -e
macOS:    brew install --cask tailscale-app
Linux:    curl -fsSL https://tailscale.com/install.sh | sh
Prüfen:   tailscale status
```

**VS Code mit Remote-SSH** — Editor, der auf dem Dev-Server arbeitet.
Quellen: [code.visualstudio.com](https://code.visualstudio.com/download),
[Remote-SSH](https://code.visualstudio.com/docs/remote/ssh).

```
Windows:  winget install --id Microsoft.VisualStudioCode -e
macOS:    brew install --cask visual-studio-code
Linux:    sudo snap install code --classic
alle:     code --install-extension ms-vscode-remote.remote-ssh
```

**SSH-Schlüssel** — ein Schlüssel je Gerät, mit Passphrase.

```
alle:     ssh-keygen -t ed25519
Prüfen:   ls ~/.ssh/id_ed25519.pub
```

**Ordner:**

```
Windows:      mkdir $HOME\Code, $HOME\Tresor
macOS/Linux:  mkdir -p ~/Code ~/Tresor && chmod 700 ~/Tresor
```

**Marketplace und Plugin** — der Standard selbst. Kein GitHub-Konto nötig.

```
claude plugin marketplace add CoreVision-Systems-GmbH/coding-plugins
claude plugin install coding-standard@corevision --scope user
Prüfen:   claude plugin list      → coding-standard@corevision
```

Danach die automatische Aktualisierung einschalten (A.9.1).

### A.5.2 Stack-Werkzeuge

**PHP 8.4 mit `intl`, Composer, Laravel-Installer** (laravel, wordpress).
Quellen: [herd.laravel.com](https://herd.laravel.com) (Windows, macOS),
[php.net](https://www.php.net/downloads), [getcomposer.org/download](https://getcomposer.org/download/),
[laravel.com/docs/installation](https://laravel.com/docs/installation),
Ubuntu: [PPA ondrej/php](https://launchpad.net/~ondrej/+archive/ubuntu/php), Debian: [packages.sury.org](https://packages.sury.org/php/).

```
Windows:  winget install --id BeyondCode.Herd -e   → Herd einmal starten, PHP 8.4 wählen
macOS:    brew install php@8.4 composer && brew link --force php@8.4
          composer global require laravel/installer
Linux:    sudo apt install php8.4-cli php8.4-intl php8.4-mbstring php8.4-xml php8.4-zip \
               php8.4-curl php8.4-sqlite3 php8.4-pgsql php8.4-mysql php8.4-gd php8.4-bcmath unzip
          Composer nach getcomposer.org/download (Installer mit Prüfsumme)
          composer global require laravel/installer
Prüfen:   php -v   ·   php -m | grep intl   ·   composer --version   ·   laravel --version
```

**Node.js 24** (laravel, astro). Quelle: [nodejs.org/en/download](https://nodejs.org/en/download),
Linux: [NodeSource](https://github.com/nodesource/distributions).

```
Windows:  winget install --id OpenJS.NodeJS.LTS -e
macOS:    brew install node@24 && brew link --force node@24
Linux:    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt install nodejs
Prüfen:   node -v    → v24.x
```

**Python 3.12** (fastapi, script). Quelle: [python.org/downloads](https://www.python.org/downloads/).
Die Vorlagen rufen `python`, nicht `python3` oder `py`.

```
Windows:  winget install --id Python.Python.3.12 -e --override "/quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1"
macOS:    brew install python@3.12, dann $(brew --prefix python@3.12)/libexec/bin in den PATH
Linux:    sudo apt install python3 python3-venv python3-pip python-is-python3
Prüfen:   python --version   → 3.12 oder neuer
```

**pipx, ruff, pytest** (script). Quellen: [pipx.pypa.io](https://pipx.pypa.io),
[docs.astral.sh/ruff](https://docs.astral.sh/ruff/), [docs.pytest.org](https://docs.pytest.org).

```
Windows:  python -m pip install --user pipx && python -m pipx ensurepath
macOS:    brew install pipx && pipx ensurepath
Linux:    sudo apt install pipx && pipx ensurepath
alle:     pipx install ruff && pipx install pytest
```

**ShellCheck** (script). Quelle: [shellcheck.net](https://www.shellcheck.net).

```
Windows:  winget install --id koalaman.shellcheck -e
macOS:    brew install shellcheck
Linux:    sudo apt install shellcheck
```

**PowerShell mit PSScriptAnalyzer** (script; von Hand genügt es, wenn das Repo `*.ps1` enthält).
Quellen: [PowerShell installieren](https://learn.microsoft.com/powershell/scripting/install/installing-powershell),
[PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview).

```
Windows:  Install-Module PSScriptAnalyzer -Scope CurrentUser     (in Windows PowerShell)
macOS:    brew install powershell, dann in pwsh dasselbe
Linux:    Paket powershell aus packages.microsoft.com, dann in pwsh dasselbe
```

**Docker — nur im Notfall** auf dem Arbeitsplatz (Container laufen auf dem Dev-Server).
Quellen: [docs.docker.com/desktop](https://docs.docker.com/desktop/),
[docs.docker.com/engine/install](https://docs.docker.com/engine/install/),
WSL2: [learn.microsoft.com/windows/wsl/install](https://learn.microsoft.com/windows/wsl/install).
Docker Desktop ist für kleine Unternehmen, Privatleute und Ausbildung kostenlos; größere
Unternehmen brauchen ein Abo — [Bedingungen](https://www.docker.com/pricing/).

```
Windows:  (Administrator) wsl --install, neu starten; winget install --id Docker.DockerDesktop -e
macOS:    brew install --cask docker-desktop
Linux:    curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker $USER
```

## A.6 Handgriffe

Schritte, die kein Skript für dich tun kann oder darf. Das Skript nennt sie am Ende einzeln
(`HAND`); `--check` zählt sie als offen, bis sie erledigt sind.

### A.6.1 Claude Code anmelden

`claude` in einem Terminal starten, im Browser mit dem Konto aus A.1 anmelden. Kontrolle:
`claude auth status` zeigt `"loggedIn": true`. Auf dem Dev-Server meldest du dich dort ebenso an.

### A.6.2 GitHub anmelden

```
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
```

Der erste Befehl zeigt einen Code und öffnet github.com; der zweite lässt `git push` und
`git clone` diese Anmeldung benutzen. Kontrolle: `gh auth status`. Auf dem Dev-Server ebenso.

### A.6.3 Git-Identität setzen

Jeder Commit trägt Name und Adresse — auf dem Arbeitsplatz und auf dem Dev-Server:

```
git config --global user.name "Vorname Nachname"
git config --global user.email "du@firma.tld"
```

### A.6.4 Tresor-Datei übernehmen

Geheimnisse liegen in KeePassXC — nie im Repository, nie in Chat, Mail oder Ticket.

1. Du bekommst von CoreVision eine eigene Datei `<name>.kdbx`; das Master-Passwort kommt
   getrennt auf einem zweiten Weg (Telefon, persönlich).
2. Datei nach `~/Tresor/` legen und in KeePassXC öffnen.
3. Werte, die ein Projekt braucht, trägst du in dessen `.env` auf dem Dev-Server ein (aus
   `.env.example` abgeleitet); `.env` ist in `.gitignore`.
4. Neue Geheimnisse meldest du CoreVision — die Firmen-Fassung pflegt CoreVision.

### A.6.5 Tailscale und Dev-Server

1. Tailscale öffnen und mit deinem eigenen Konto anmelden. Jeder Server von CoreVision hat sein
   eigenes Tailnet; die Freigabe (Sharing) für den Dev-Server kommt per Einladung — annehmen,
   dann erscheint er in deinem Tailnet unter `<server>.tailXXXX.ts.net`. Weitere Server kommen
   einzeln dazu, Entzug heißt: Freigabe widerrufen (B.2).
2. Den öffentlichen Schlüssel `~/.ssh/id_ed25519.pub` an CoreVision schicken — daraus entsteht dein
   Konto auf dem Dev-Server (B.5).
3. In VS Code: Befehlspalette → „Remote-SSH: Connect to Host…“ → `<name>@<dev-server>`, dann
   den Ordner `~/Code` öffnen. Ein Eintrag in `~/.ssh/config` spart das Tippen:

   ```
   Host dev
       HostName <dev-server>        # voller Name <server>.tailXXXX.ts.net oder 100.x-Adresse
       User <name>
   ```

### A.6.6 Herd einmal starten (Windows, nur bei lokalen PHP-Werkzeugen)

Herd aus dem Startmenü öffnen; es richtet PHP 8.4, Composer und den Laravel-Installer ein. In Herd
Version 8.4 wählen, dann eine **neue** PowerShell — `php -m` zeigt `intl`.

### A.6.7 Rechte auf die Firmen-Repositories

GitHub-Benutzernamen an CoreVision schicken, Einladung in `CoreVision-Systems-GmbH` annehmen.
Kontrolle: `gh repo list CoreVision-Systems-GmbH` zeigt dein Projekt.

## A.7 Erstes Projekt

Auf dem Dev-Server (VS Code mit Remote-SSH, Terminal dort):

```
gh repo clone CoreVision-Systems-GmbH/<projekt> ~/Code/<projekt>
cd ~/Code/<projekt>
claude
```

`core.hooksPath` ist lokale Git-Konfiguration und reist nicht mit dem Klon. Seit Plugin 1.1.0
setzt der erste Sessionstart von Claude Code im Klon sie selbst (`.githooks`, nur an der Wurzel
des Repos und nur für den gitleaks-Hook der Vorlage). Wer vor dem ersten Claude-Start im Terminal
committet, setzt sie von Hand: `git config core.hooksPath .githooks`. Der Hook warnt nur, wenn
gitleaks fehlt; die CI prüft in jedem Fall.

Beim ersten Start fragt Claude Code, ob du dem Ordner und dem Marketplace `corevision` vertraust
— ja. Danach meldet es „Firmenstandard coding-standard@corevision gilt in diesem Repo (Stack
erkannt: …)“ und liest Kern und Stack-Regeln.

Die Befehle des Projekts stehen in seiner `CLAUDE.md` unter „Befehle“. Erste Schritte meist:
Abhängigkeiten installieren, `.env` aus `.env.example` ableiten (mit `APP_DOMAIN` und Werten aus
dem Tresor), dann alle Prüfungen — und die Dev-Instanz starten:

```
deploy/dev.sh up        → https://dev.<APP_DOMAIN>
```

**Erst wenn die Prüfungen auf dem unveränderten Stand grün sind, beginnt die Arbeit.** Nach der
Abnahme auf `dev.<domain>`: PR, Merge, Release — und der Rollout (Teil E).

## A.8 Kontrolle

```
Windows:      & ([scriptblock]::Create((irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1))) -Check
macOS/Linux:  curl -fsSL https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.sh | bash -s -- --check
```

Mit `--stack <name>` prüft sie zusätzlich die Werkzeuge des Stacks. Geprüft werden
Grundausstattung und Fassungen, Ordner, Plugin und automatische Aktualisierung, Anmeldungen,
Git-Identität, auf dem Arbeitsplatz Tailscale, VS Code, Remote-SSH und SSH-Schlüssel. Exit 0 und
„Das Gerät erfüllt den Standard“ heißt: fertig; sonst ist der Exit-Code die Zahl der offenen Punkte.

## A.9 Aktualisieren

### A.9.1 Der Standard — automatisch

Jede neue Fassung erscheint als Release in
[`CoreVision-Systems-GmbH/coding-plugins`](https://github.com/CoreVision-Systems-GmbH/coding-plugins).
Mit automatischer Aktualisierung prüft Claude Code **einmal je Session** — nach der ersten
Nachricht, mit einigen Minuten Verzögerung — und holt sie; sie gilt ab der **nächsten** Session.
Eine Session, die tagelang offen bleibt, arbeitet so lange mit dem alten Stand. Eingeschaltet über
`autoUpdate` in `~/.claude/settings.json` — das Skript setzt ihn:

```json
"extraKnownMarketplaces": {
  "corevision": {
    "source": { "source": "github", "repo": "CoreVision-Systems-GmbH/coding-plugins" },
    "autoUpdate": true
  }
}
```

Von Hand: `/plugin` → Marketplaces → `corevision` → „Enable auto-update“. Achtung:
`claude plugin marketplace add` schreibt den Eintrag neu und verliert `autoUpdate` — danach wieder
einschalten oder das Skript erneut starten. Sofort, von Hand — danach Claude Code neu starten:

```
claude plugin marketplace update corevision
claude plugin update coding-standard@corevision --scope user
```

`--scope user` gehört dazu: Ohne die Angabe hebt der Befehl in einem Projektordner mit eigenem
Eintrag nur diesen, geladen wird aber der Eintrag im User-Scope. Steht der Standard nur als
Projekt-Eintrag auf dem Gerät (Projekt geklont, ohne Einrichtung), scheitert der Befehl — dann
einmal `claude plugin install coding-standard@corevision --scope user`; das Skript tut das selbst
und meldet bei `--check` den fehlenden User-Eintrag.

Server-Befehle (`setup-server.sh`, `edge-site`, `rollout`) kommen mit
`sudo git -C /opt/corevision/standard pull` in neuer Fassung (B.6).

### A.9.2 Claude Code und die Werkzeuge

Claude Code aktualisiert sich selbst. Werkzeuge aktualisiert der Paketmanager
(`winget upgrade --all`, `brew upgrade`, `sudo apt upgrade`); das Skript tauscht Vorhandenes nicht
aus — `--check` meldet eine zu alte Fassung.

## A.10 Fehlerbilder

| Zeichen | Ursache | Abhilfe |
|---|---|---|
| Filament-Tests enden mit HTTP 500, `php -m` ohne `intl` | PHP ohne `intl` im PATH — unter Windows oft „herd-lite“ | Herd öffnen, PHP 8.4 wählen, neue Shell |
| `python` öffnet den Microsoft Store | App-Ausführungsalias verdeckt das echte Python | Einstellungen → Apps → Erweiterte App-Einstellungen → App-Ausführungsaliase: `python.exe`, `python3.exe` aus |
| „nicht im Pfad“ direkt nach der Installation | Die laufende Shell kennt neue Programme noch nicht | Neue Shell öffnen, Skript erneut starten |
| `irm … \| iex` bricht mit „Unerwartetes Attribut CmdletBinding“ ab | Skript mit BOM gespeichert (nur lokale Kopien) | Original-URL verwenden |
| VS Code: „Could not establish connection“ zum Dev-Server | Tailscale nicht verbunden, Freigabe des Servers fehlt oder wurde widerrufen, Schlüssel nicht hinterlegt | `tailscale status` — fehlt der Server dort, Freigabe bei CoreVision anfragen (A.6.5); Schlüssel an CoreVision |
| `https://dev.<domain>` nicht erreichbar | Tailscale aus, Freigabe des Dev-Servers fehlt, Dev-Instanz läuft nicht | Tailscale an, `tailscale status` zeigt den Server; auf dem Dev-Server `deploy/dev.sh status`, `sudo edge-site check <domain>` |
| Beim Start kein Hinweis „Firmenstandard … gilt“ | Ordner nicht vertraut, oder das Projekt erklärt den Standard nicht | Claude Code im Projektordner neu starten und vertrauen |
| `claude plugin install` findet das Plugin nicht | Marketplace-Kopie veraltet | `claude plugin marketplace update corevision` |
| Das Skript bricht unter Git Bash ab | `setup.sh` ist nicht für Windows | `setup.ps1` in der PowerShell |
| Beim Commit „pre-commit: gitleaks fehlt“ | Scanner nicht installiert oder nicht im PATH | Skript erneut starten (Grundausstattung) oder A.5.1; neue Shell |
| Der Commit geht durch, obwohl `.githooks/pre-commit` da ist | `core.hooksPath` in diesem Klon nicht gesetzt (noch keine Claude-Session im Klon gestartet, oder global gesetzt) | Claude Code einmal starten oder `git config core.hooksPath .githooks` (A.7) |

Hilft nichts davon: Ausgabe des Skripts und von `--check` als Issue in
[`coding-plugins`](https://github.com/CoreVision-Systems-GmbH/coding-plugins/issues) melden.

## A.11 Rückweg

```
claude plugin uninstall coding-standard@corevision
claude plugin marketplace remove corevision
```

`~/.claude/settings.json.bak-setup` enthält den Stand vor dem ersten Lauf. Werkzeuge entfernst du
mit `winget uninstall --id <Id>`, `brew uninstall <paket>` bzw. `sudo apt remove <paket>`; die
PATH-Zeilen stehen unter `# Augmented Coding (setup.sh)` in `~/.zshrc` bzw. `~/.bashrc`.
`~/Code` und `~/Tresor` löscht das Skript nie.

---

# Teil B — Dev-Server

Einmal einzurichten, von jemandem mit root-Zugang. Ergebnis: ein Ubuntu-Server im Tailnet mit
Docker Compose und Edge-Caddy, auf dem jede Person ein eigenes Konto hat und Anwendungen unter
`https://dev.<domain>` testet.

## B.1 Voraussetzungen

| Was | Warum |
|---|---|
| Ubuntu **26.04 LTS** (oder 24.04 LTS), frisch, mit root-Zugang | darauf ist `setup-server.sh` gebaut; andere Systeme nach dem Skript von Hand |
| 4 vCPU, 8–16 GB RAM, 80 GB SSD als Anfang | mehrere Dev-Instanzen samt Datenbanken und Abbild-Bau |
| Ein eigenes GitHub-Konto für diesen Server (mit 2FA, im Tresor) | meldet das eigene Tailnet des Servers an — ein Konto, ein Tailnet, ein Server |
| Eine Domain und der DNS-Weg aus Teil D | Zertifikate über DNS-01 |

## B.2 Einrichten

```bash
sudo apt-get update && sudo apt-get install -y git
sudo git clone https://github.com/CoreVision-Systems-GmbH/coding-plugins /opt/corevision/standard
sudo /opt/corevision/standard/plugins/coding-standard/server/setup-server.sh \
     --rolle dev --dns hetzner --email admin@<deine-domain>
```

`--dns` ist `hetzner`, `cloudflare` oder `acmedns` (Teil D). Den API-Token fragt das Skript
verdeckt ab — nie als Argument. Was es tut, jeweils nur, wenn es noch fehlt:

1. Grundpakete: `curl git jq ufw unattended-upgrades`.
2. **Docker mit Compose** aus dem offiziellen apt-Repo ([Anleitung](https://docs.docker.com/engine/install/ubuntu/)),
   nicht über `get.docker.com`.
3. **Tailscale** aus dem offiziellen apt-Repo ([Anleitung](https://tailscale.com/kb/1031/install-linux)).
4. Kernel-Einstellung `net.ipv4.ip_nonlocal_bind = 1` — damit der Edge nach einem Neustart auch
   dann startet, wenn Tailscale später hochkommt.
5. **Firewall (ufw):** alles zu, außer über `tailscale0`. SSH bleibt öffentlich offen, bis du über
   das Tailnet verbunden bist — dann schließt ein erneuter Lauf es (kein Aussperren).
6. `/etc/corevision/server.env` (Rolle, DNS-Weg, Kontakt, Ziel-IP) und **`/opt/edge/`** mit dem
   Edge-Caddy: gebaut aus `server/edge/Dockerfile` (Caddy mit den DNS-Modulen, gepinnt), gestartet
   im Netz `edge`, **gebunden nur an die Tailscale-IP** — Docker umgeht ufw für veröffentlichte
   Ports, deshalb schützt allein die Bindung.
7. Befehle `edge-site` und `rollout` unter `/usr/local/bin`; sudo-Regel, damit Mitglieder der
   Gruppe `docker` `edge-site` ohne Passwort aufrufen dürfen.
8. Prüfung — wie `--check`.

**Handgriff:** `sudo tailscale up` (Link im Browser öffnen) und **mit dem GitHub-Konto dieses
Servers** anmelden — so entsteht sein eigenes Tailnet mit ihm als einzigem Host. Teile ihn
zuerst **dir selbst** (Admin-Konsole des Servers → Machines → Share → Einladung an dein eigenes
Tailnet annehmen), sonst erreichst du ihn nicht über Tailscale; jede weitere Person mit Zugriff
bekommt ihre eigene Freigabe, Entzug heißt Freigabe widerrufen. Das gilt genauso für jeden Spark
(Rechner für lokale Modelle) und jeden anderen Linux-Server. Dann das Skript erneut starten.
Danach **über das Tailnet** neu verbinden (`ssh <name>@<tailscale-ip>`) und das Skript noch einmal
starten — erst wenn die Sitzung nachweislich aus dem Tailnet kommt, schließt es SSH nach außen.
Aus der Konsole des Anbieters oder ohne erkennbare Gegenstelle bleibt Port 22 offen. Kontrolle:

```bash
sudo /opt/corevision/standard/plugins/coding-standard/server/setup-server.sh --check
```

## B.3 Stack-Werkzeuge und Claude Code

Auf dem Dev-Server wird entwickelt — er braucht die Stack-Werkzeuge. **Einmal als Admin**
(ein Konto mit sudo; die Pakete gelten für alle):

```bash
curl -fsSL https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.sh | bash -s -- --stack alle
```

Das Skript erkennt den Server an `/etc/corevision/server.env` und lässt VS Code, Tailscale und den
SSH-Schlüssel weg. **Je Entwickler** (Konten aus B.5 haben kein sudo) genügen danach Claude Code
und das Plugin — derselbe Aufruf ohne `--stack` installiert sie ins eigene Konto, apt-Schritte
entfallen, weil die Pakete schon da sind — und die Anmeldungen A.6.1 bis A.6.3.

## B.4 Dev-Instanz einer Anwendung

Im Projekt auf dem Dev-Server:

```bash
cp .env.example .env          # APP_DOMAIN und Werte aus dem Tresor eintragen
deploy/dev.sh up              # baut aus dem Arbeitsstand, startet, schließt an
```

`deploy/dev.sh` baut das Abbild aus dem Arbeitsordner (`compose.build.yaml`), startet den Verbund
mit eigenen Container-Namen und eigener Datenbank (`compose.dev.yaml`, Projekt `<name>-dev`),
bringt bei Laravel das Schema auf den Stand und ruft beim ersten Mal
`sudo edge-site add <APP_DOMAIN> <name>-dev-app:8080` auf. Nach jeder Änderung erneut
`deploy/dev.sh up`; `deploy/dev.sh logs`, `status`, `down`. Eine Dev-Instanz je Anwendung.

## B.5 Konten für Entwickler

```bash
sudo adduser --disabled-password <name>
sudo usermod -aG docker <name>          # Container bauen und starten (root-gleich!)
sudo install -d -m 700 -o <name> -g <name> /home/<name>/.ssh
echo "<öffentlicher Schlüssel>" | sudo tee /home/<name>/.ssh/authorized_keys >/dev/null
sudo chown <name>: /home/<name>/.ssh/authorized_keys && sudo chmod 600 /home/<name>/.ssh/authorized_keys
```

Die Gruppe `docker` ist root-gleich — nur Personen aufnehmen, denen du den Server anvertraust.

## B.6 Den Standard auf dem Server aktualisieren

```bash
sudo git -C /opt/corevision/standard pull
sudo /opt/corevision/standard/plugins/coding-standard/server/setup-server.sh
```

Der zweite Aufruf übernimmt die gespeicherten Werte; neue Edge-Fassungen (Dockerfile) werden
gebaut, sonst ändert sich nichts.

---

# Teil C — Prod-Server

Gleich gebaut wie der Dev-Server, mit drei Unterschieden: öffentlich auf 80/443, Adressen ohne
`dev.`, und Fassungen kommen nur als Release per `rollout` (Teil E).

## C.1 Einrichten

```bash
sudo apt-get update && sudo apt-get install -y git
sudo git clone https://github.com/CoreVision-Systems-GmbH/coding-plugins /opt/corevision/standard
sudo /opt/corevision/standard/plugins/coding-standard/server/setup-server.sh \
     --rolle prod --dns hetzner --email admin@<deine-domain>
```

Unterschiede zu B.2: ufw öffnet 80/443 öffentlich; der Edge bindet an alle Adressen; die
A-Records zeigen auf die öffentliche IPv4 (Standardroute, sonst `--ip <adresse>`). SSH nur über
Tailscale, wie auf Dev. Kontrolle mit `--check`.

## C.2 GitHub-Zugang für Rollouts

`rollout` liest Releases und Lieferdateien über die GitHub-API, Abbilder kommen aus GHCR. Zwei
Tokens, jeweils **nur Leserecht**, beide verdeckt eingeben — nie als Argument, nie per `echo`:

| Zweck | Token | Rechte |
|---|---|---|
| Releases und Lieferdateien (`rollout`) | fine-grained, nur die App-Repos | Contents: Read-only |
| Abbilder aus GHCR (`docker login`) | klassisch, von einem Maschinenkonto | nur `read:packages` |

Kein Token mit Schreibrecht auf dem Server: Wer ihn kompromittiert, könnte sonst in Firmen-Repos
schreiben.

```bash
sudo rollout token                                  # fragt verdeckt
sudo docker login ghcr.io -u <maschinenkonto>       # fragt verdeckt nach dem Passwort (= Token)
```

## C.3 Anwendung einrichten (einmal je Anwendung)

```bash
sudo rollout <app> einrichten CoreVision-Systems-GmbH/<repo>
#   → holt compose.yaml, .env.example und deploy/ des neuesten Releases nach /opt/apps/<app>/
sudo cp /opt/apps/<app>/.env.example /opt/apps/<app>/.env
sudo nano /opt/apps/<app>/.env        # APP_VERSION (der genannte Tag ohne v), APP_DOMAIN, Werte aus dem Tresor
cd /opt/apps/<app> && sudo deploy/install.sh
```

`deploy/install.sh` ist die Erstinstallation (bei WordPress samt Site); es schließt die
Anwendung mit `edge-site` unter `APP_DOMAIN` an. Kontrolle: `sudo edge-site check <APP_DOMAIN>`.
Jede weitere Fassung kommt danach nur noch über `rollout` (Teil E).

---

# Teil D — DNS und Zertifikate

Zertifikate holt der Edge-Caddy über **ACME DNS-01**: Let's Encrypt prüft einen TXT-Eintrag unter
`_acme-challenge.<host>`, den Caddy selbst setzt. Der Server muss dafür nicht erreichbar sein —
deshalb bekommt auch der Dev-Server im Tailnet echte Zertifikate. Caddy erneuert sie rund 30 Tage
vor Ablauf allein. Drei Wege:

## D.1 Hetzner (DNS in der Hetzner Console)

1. [console.hetzner.com](https://console.hetzner.com) → Projekt → Security → API Tokens → Token
   mit **Lesen und Schreiben** anlegen (ein reiner Lese-Token scheitert).
2. `setup-server.sh … --dns hetzner` fragt ihn ab und legt ihn in `/opt/edge/.env` (600).
3. `edge-site add` setzt den A-Record über die [Hetzner-API](https://docs.hetzner.cloud/) selbst;
   das Zertifikat kommt über [caddy-dns/hetzner](https://github.com/caddy-dns/hetzner).

## D.2 Cloudflare

1. [dash.cloudflare.com](https://dash.cloudflare.com/profile/api-tokens) → API Tokens → „Create
   Token“ mit **Zone → Zone → Read** und **Zone → DNS → Edit**, beschränkt auf deine Zone.
2. `setup-server.sh … --dns cloudflare` fragt ihn ab.
3. `edge-site add` setzt den A-Record (ohne Cloudflare-Proxy, „DNS only“); Zertifikat über
   [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare).

## D.3 Anbieter ohne API — acme-dns (einmal CNAME, danach automatisch)

Für Registrare ohne DNS-API: Die Prüfung wird per CNAME an einen
[acme-dns](https://github.com/acme-dns/acme-dns)-Server delegiert, den Caddy per API bedient.

1. `setup-server.sh … --dns acmedns --acmedns-url https://<dein-acme-dns>` — ohne Angabe der
   öffentliche Dienst `auth.acme-dns.io`, laut Projekt **nur zum Testen**. Für den Betrieb einen
   eigenen acme-dns-Server (braucht einen öffentlich erreichbaren Port 53 und einen NS-Eintrag).
2. `sudo edge-site add <host> <container>:<port>` registriert den Host und gibt **genau zwei
   Einträge** aus, die du einmal beim Anbieter setzt:

   ```
   <host>                 A      <ziel-ip>
   _acme-challenge.<host> CNAME  <id>.<acme-dns-domain>.
   ```

3. Sobald der CNAME sichtbar ist, holt Caddy das Zertifikat; `sudo edge-site check <host>` belegt
   es. Danach keine Handgriffe mehr — auch keine bei der Erneuerung.

## D.4 Kontrolle

```bash
sudo edge-site list
sudo edge-site check <host>     # DNS → Ziel-IP, Zertifikat von Let's Encrypt, HTTPS-Status
docker logs edge-caddy          # bei Zertifikatsproblemen: was Caddy versucht hat
```

---

# Teil E — Rollout auf den Prod-Server

Der Prod-Server holt eine Fassung **nur auf Auftrag** — es gibt keinen dauerhaften Timer.

| Befehl (auf dem Prod-Server) | Wirkung |
|---|---|
| `sudo rollout <app> jetzt [tag]` | spielt sofort ein; ohne Tag das neueste Release |
| `sudo rollout <app> planen "JJJJ-MM-TT HH:MM" [tag]` | einmaliger Termin (Europe/Vienna); ohne Tag wird das neueste Release **beim Planen** festgeschrieben |
| `sudo rollout liste` | geplante Termine mit Id, Anwendung und Tag |
| `sudo rollout absagen <id>` | Termin entfernen |
| `sudo rollout <app> status` | laufende Fassung, Container, Termine, letzte Läufe |

Vom Arbeitsplatz aus mit Claude Code: **`/rollout <app> jetzt`** oder
**`/rollout <app> "2026-10-03 02:00"`** — der Skill zeigt die Änderungen seit der laufenden
Fassung, fragt nach der Freigabe und führt den Auftrag per SSH aus.

Ablauf eines Rollouts: Release prüfen → `compose.yaml` und `deploy/` des Tags nach
`/opt/apps/<app>/` (die `.env` bleibt) → `deploy/update.sh <tag>`: Sicherung, Abbild laden,
Migration, Start, Zustandsprüfung. Scheitert er, nennt er den Rückweg:

```bash
sudo rollout <app> jetzt <vorheriger-tag>
```

Termine sind Timer-Einheiten unter `/etc/systemd/system/rollout-*.timer`: Sie überstehen einen
Neustart und entfernen sich nach dem Lauf. Protokoll: `/var/log/corevision/rollout.log`. Vor einem
Rollout mit Migration oder neuen ENV-Schlüsseln: `/deploy-check`.

---

## Rückweg für die Server

```bash
docker compose -f /opt/edge/compose.yaml down        # Edge anhalten
sudo ufw disable                                     # Firewall aus
sudo rollout liste; sudo rollout absagen <id>        # offene Termine entfernen
```

`setup-server.sh` löscht nichts. Pakete mit `sudo apt remove`, Zertifikate liegen unter
`/var/lib/edge/data`, Konfiguration unter `/opt/edge` und `/etc/corevision`.
