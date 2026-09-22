# Einrichtung — ein neues Gerät für Augmented Coding

Dieses Kochbuch führt dich von einem frischen Windows-, macOS- oder Linux-Rechner zu einem
Arbeitsplatz, an dem Claude Code nach dem Firmenstandard der CoreVision Systems GmbH arbeitet.
Du brauchst dafür nichts außer diesem Repository — keinen Zugang zu internen Laufwerken und
keine Vorlage von einem anderen Rechner.

Es gibt zwei Wege zum selben Ergebnis:

- **Weg A — das Einrichtungsskript.** Ein Befehl installiert alles, was sich ohne Menschen
  installieren lässt, und nennt am Ende die wenigen Handgriffe, die nur du tun kannst.
  Etwa 15 bis 45 Minuten, je nach Stack und Leitung.
- **Weg B — von Hand.** Dieselben Schritte einzeln, mit Quelle und Prüfbefehl je Werkzeug.
  Für Rechner, auf denen das Skript nicht laufen darf oder nicht durchkommt.

Beide Wege enden mit derselben Kontrolle: `setup … --check` (Abschnitt 8). Endet sie mit
„Das Gerät erfüllt den Standard“, bist du fertig.

**Inhalt:** 1 Voraussetzungen · 2 Verzeichnisstruktur · 3 Stacks · 4 Weg A: Skript ·
5 Weg B: von Hand · 6 Handgriffe · 7 Erstes Projekt · 8 Kontrolle · 9 Aktualisieren ·
10 Fehlerbilder · 11 Rückweg

---

## 1. Voraussetzungen

| Was | Warum | Woher |
|---|---|---|
| Windows 10 22H2 oder 11, macOS 13 oder neuer, Ubuntu 24.04 oder neuer, Debian 13 | darauf ist das Skript ausgelegt. Ubuntu 22.04 und Debian 12 bringen nur Python 3.10 bzw. 3.11 mit — für `fastapi` und `script` dort Python 3.12 nach Weg B installieren; andere Linux-Systeme ganz über Weg B | — |
| Ein Benutzerkonto mit Recht auf Installationen | Windows: winget fragt per Benutzerkontensteuerung nach (Herd, Node, Docker Desktop, KeePassXC), WSL2 braucht eine Administrator-PowerShell. macOS: Administratorkonto (Homebrew fragt nach deinem Passwort). Linux: `sudo` | deine IT |
| GitHub-Konto mit **Zwei-Faktor-Anmeldung** | für die Arbeit an unseren Repositories; zum Installieren des Standards nicht nötig | [github.com/signup](https://github.com/signup), 2FA unter Settings → Password and authentication |
| Claude-Abo mit Claude Code | Pro, Max, Team, Enterprise oder ein Console-Konto (API); der kostenlose Tarif enthält Claude Code nicht | [claude.com/pricing](https://claude.com/pricing) — klären wir mit dir |
| Einladung in die Organisation `CoreVision-Systems-GmbH` | Lese- und Schreibrecht auf dein Projekt | bekommst du von CoreVision, sobald dein GitHub-Name bekannt ist |
| Deine Tresor-Datei (`.kdbx`) | die Geheimnisse deines Projekts (Abschnitt 6.4) | bekommst du von CoreVision |

---

## 2. Verzeichnisstruktur

Der Standard setzt genau zwei Ordner voraus. Das Skript legt sie an; von Hand geht es mit
`mkdir`.

| Ordner | Windows | macOS / Linux | Zweck |
|---|---|---|---|
| `~/Code` | `C:\Users\<du>\Code` | `/Users/<du>/Code`, `/home/<du>/Code` | **ein Unterordner je Projekt**: `~/Code/<projekt>`. Hier klont `gh repo clone` hin, hier legt `/projekt-neu` neue Projekte an. |
| `~/Tresor` | `C:\Users\<du>\Tresor` | `~/Tresor` (Rechte `700`) | deine KeePassXC-Datei `<name>.kdbx`. Nur für dich, nie in einem Repository. |

Dazu kommen Ordner, die die Werkzeuge selbst verwalten — nicht von Hand ändern:

| Ordner | Wer | Inhalt |
|---|---|---|
| `~/.claude/` | Claude Code | `settings.json` (deine Einstellungen), `plugins/` (Marketplace und Plugin-Cache: `plugins/cache/corevision/coding-standard/<fassung>/`) |
| `~/.local/bin` | Claude Code, pipx, Composer unter Linux | Programme ohne Administrator |
| `~/.config/herd/` | Herd (Windows) | PHP 8.4, Composer, Laravel-Installer |

Warum genau so:

- **`Code` mit großem C.** Unter macOS und Linux sind `Code` und `code` zwei verschiedene
  Ordner; `/projekt-neu` schreibt nach `~/Code`. Unter Windows ist das egal.
- **Nicht in OneDrive, iCloud oder Dropbox.** Synchronisierte Ordner vertragen `.git`,
  `node_modules` und `vendor` schlecht (Sperren, halbe Stände, Konflikte). Gesichert wird der
  Code über GitHub, nicht über den Sync.
- **Nichts sonst ist Pflicht.** Ein Notiz-Vault (Obsidian o. Ä.) ist persönlich und optional;
  wer einen führt, gibt ihn `/projekt-neu` mit `--vault <pfad>` mit. Das `deployments`-Repo
  brauchen nur die, die Kundeninstanzen ausrollen — CoreVision sagt dir, ob das dich betrifft.

---

## 3. Stacks — was du wirklich brauchst

Welcher Stack dein Projekt ist, steht in seiner Datei `.coding-standard` oder in der
`CLAUDE.md`; im Zweifel fragst du. Das Skript installiert die **Grundausstattung** immer und die
Werkzeuge eines Stacks nur, wenn du ihn mit `--stack` bzw. `-Stack` wählst.

| Baustein | laravel | wordpress | astro | fastapi | script | Fassung |
|---|:-:|:-:|:-:|:-:|:-:|---|
| PHP mit `intl` | ● | ● | | | | 8.4 oder neuer |
| Composer | ● | ● | | | | 2 |
| Laravel-Installer | ● | | | | | aktuell |
| Node.js | ● | | ● | | | 24 (mindestens 22.12) |
| Docker mit Compose v2 | ● | ● | ● | ● | | aktuell |
| Python | | | | ● | ● | 3.12 oder neuer, Befehl `python` |
| pipx mit ruff und pytest | | | | | ● | aktuell |
| ShellCheck | | | | | ● | aktuell |
| PowerShell mit PSScriptAnalyzer | | | | | ● | 7 bzw. Windows PowerShell 5.1 |

**Grundausstattung** (jeder Stack): Git (unter Windows mit Git Bash — die Hooks des Standards
sind bash-Skripte), GitHub CLI `gh`, Claude Code, KeePassXC, die Ordner aus Abschnitt 2,
der Marketplace `corevision` mit dem Plugin `coding-standard` und automatischer Aktualisierung.

Nicht nötig sind: jq, eine lokale Datenbank (PostgreSQL und MariaDB laufen als Container),
wp-cli (liegt im Abbild). FastAPI-Projekte bringen ruff, mypy und pytest über
`requirements-dev.txt` in ihre eigene `.venv` mit.

**Fassungen:** CI und Abbilder laufen auf PHP 8.4, Node 24 und Python 3.12. Installiert wird
die neueste Fassung innerhalb dieser Linie; wer lokal dieselbe hat, sieht dieselben Fehler wie
CI und Server. Neuere lokale Fassungen (Node 26, Python 3.13) funktionieren meist, die
Kontrolle warnt dann.

---

## 4. Weg A — das Einrichtungsskript

### 4.1 Aufruf

**Windows** — eine gewöhnliche PowerShell öffnen (kein Administrator):

```powershell
irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1 | iex
```

Mit Stack und GitHub-Anmeldung (Skript laden, dann aufrufen):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1))) -Stack laravel -GitHubLogin
```

**macOS, Linux, WSL** — ein Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.sh | bash -s -- --stack laravel --github-login
```

| Schalter (PowerShell / bash) | Wirkung |
|---|---|
| `-Stack <name>` / `--stack <name>` | zusätzlich die Werkzeuge eines Stacks: `laravel`, `fastapi`, `script`, `astro`, `wordpress` oder `alle`; mehrere mit Komma |
| `-GitHubLogin` / `--github-login` | meldet `gh` im Browser an und richtet Git so ein, dass es sich über `gh` anmeldet |
| `-DryRun` / `--dry-run` | zeigt nur, was passieren würde; ändert nichts |
| `-Liste` / `--liste` | zeigt die Bausteine der gewählten Stacks samt Quelle |
| `-Check` / `--check` | installiert nichts, prüft nur (Abschnitt 8) |

Unsicher? Erst mit `-DryRun` bzw. `--dry-run` laufen lassen und lesen, was es vorhat.

### 4.2 Was das Skript tut

In dieser Reihenfolge; alles, was schon da ist, wird übersprungen — ein zweiter Lauf schadet
nicht, er holt nur Fehlendes nach.

1. **Grundausstattung:** Git, GitHub CLI, Claude Code (nativer Installer von claude.ai, der
   sich selbst aktualisiert), KeePassXC. macOS: vorher Homebrew, falls es fehlt (fragt nach
   deinem Passwort).
2. **Ordner** `~/Code` und `~/Tresor` (Abschnitt 2).
3. **Marketplace und Plugin:** `claude plugin marketplace add CoreVision-Systems-GmbH/coding-plugins`,
   `claude plugin install coding-standard@corevision --scope user`, dann **automatische
   Aktualisierung** an (Abschnitt 9). Dafür wird `~/.claude/settings.json` ergänzt; die alte
   Fassung bleibt als `settings.json.bak-setup` liegen.
4. **Werkzeuge der gewählten Stacks** (Abschnitt 3), aus diesen Quellen:

   | Baustein | Windows (winget) | macOS (Homebrew) | Ubuntu/Debian (apt) |
   |---|---|---|---|
   | PHP, Composer, Laravel-Installer | `BeyondCode.Herd` | `php@8.4`, `composer`, dann `composer global require laravel/installer` | `php8.4-cli php8.4-intl …` (Ubuntu ohne 8.4: PPA `ondrej/php`), Composer von getcomposer.org mit Prüfsumme, Laravel-Installer per Composer |
   | Node.js | `OpenJS.NodeJS.LTS` | `node@24` | NodeSource-Repo `setup_24.x`, Paket `nodejs` |
   | Docker | `Docker.DockerDesktop` (braucht WSL2) | Cask `docker-desktop` | Skript `get.docker.com`, Gruppe `docker`; unter WSL: Docker Desktop in Windows |
   | Python | `Python.Python.3.12` mit PATH-Eintrag | `python@3.12` | `python3 python3-venv python3-pip python-is-python3` |
   | pipx, ruff, pytest | `python -m pip install --user pipx` | `pipx` | `pipx` |
   | ShellCheck | `koalaman.shellcheck` | `shellcheck` | `shellcheck` |
   | PowerShell, PSScriptAnalyzer | `Install-Module PSScriptAnalyzer -Scope CurrentUser` | `powershell`, dann dasselbe | Microsoft-Repo `packages-microsoft-prod.deb`, dann dasselbe |

5. **GitHub-Anmeldung**, wenn du `-GitHubLogin`/`--github-login` angegeben hast.
6. **Prüfung** — wie `--check`.

Auf macOS und Linux trägt das Skript neue Programmpfade (Composer, Python) am Ende von
`~/.zshrc` bzw. `~/.bashrc` ein, gekennzeichnet mit `# Augmented Coding (setup.sh)`.

### 4.3 Die Ausgabe lesen

| Kennung | Bedeutung |
|---|---|
| `ok` | vorhanden und in Ordnung |
| `mache` | wird gerade installiert oder angelegt |
| `achtung` | kein Fehler, aber bemerkenswert — z. B. Node 26 statt 24 |
| `HAND` | ein Handgriff, den nur du tun kannst — Erklärung in Abschnitt 6 |
| `FEHLT` / `FEHLER` | etwas fehlt oder ist schiefgegangen; die Zeile sagt, was zu tun ist |

Am Ende steht entweder „Fertig. Nichts mehr von Hand zu tun.“ oder die Liste
**„Jetzt noch von Hand“**. Das Skript endet mit Exit 0, wenn nur Handgriffe offen sind, und
mit Exit 1, wenn etwas nicht installiert werden konnte.

### 4.4 Wann du das Skript erneut startest

- **Nach einem Neustart**, den WSL2 oder Docker verlangt haben.
- **Nach dem ersten Start von Herd** (Windows) oder einer neuen Shell, wenn eine Zeile
  „nicht im Pfad“ meldete — neue Programme sieht erst eine neue Shell.
- **Wenn du später einen weiteren Stack brauchst:** mit `--stack <neuer stack>`.

Ein erneuter Lauf ist immer sicher: Vorhandenes bleibt, wie es ist.

---

## 5. Weg B — von Hand

Jede Zeile: Zweck, Quelle, Befehl, Prüfung. Reihenfolge wie im Skript.

### 5.1 Grundausstattung

**Git** — Versionsverwaltung; unter Windows mit Git Bash, die Claude Code und die Hooks brauchen.
Quelle: [git-scm.com/downloads](https://git-scm.com/downloads).

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

**Claude Code** — der Assistent. Der native Installer aktualisiert sich selbst im Hintergrund;
Pakete aus winget oder Homebrew tun das nicht — deshalb der native Weg.
Quelle: [code.claude.com/docs/en/setup](https://code.claude.com/docs/en/setup).

```
Windows:  irm https://claude.ai/install.ps1 | iex
macOS/Linux:  curl -fsSL https://claude.ai/install.sh | bash
Prüfen:   claude --version
```

**KeePassXC** — Tresor für Geheimnisse (Abschnitt 6.4).
Quelle: [keepassxc.org/download](https://keepassxc.org/download/).

```
Windows:  winget install --id KeePassXCTeam.KeePassXC -e
macOS:    brew install --cask keepassxc
Linux:    sudo apt install keepassxc
```

**Ordner:**

```
Windows:  mkdir $HOME\Code, $HOME\Tresor
macOS/Linux:  mkdir -p ~/Code ~/Tresor && chmod 700 ~/Tresor
```

**Marketplace und Plugin** — der Standard selbst. Kein GitHub-Konto nötig.

```
claude plugin marketplace add CoreVision-Systems-GmbH/coding-plugins
claude plugin install coding-standard@corevision --scope user
Prüfen:   claude plugin list      → coding-standard@corevision
```

Danach die automatische Aktualisierung einschalten (Abschnitt 9.1).

### 5.2 Stack-Werkzeuge

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

**Docker mit Compose v2** (laravel, wordpress, astro, fastapi) — Abbilder bauen, lokaler
Verbund mit Datenbank. Quellen: [docs.docker.com/desktop](https://docs.docker.com/desktop/),
Linux: [docs.docker.com/engine/install](https://docs.docker.com/engine/install/),
WSL2: [learn.microsoft.com/windows/wsl/install](https://learn.microsoft.com/windows/wsl/install).
Docker Desktop ist für kleine Unternehmen, Privatleute und Ausbildung kostenlos; größere
Unternehmen brauchen ein Abo — prüfe die [Bedingungen](https://www.docker.com/pricing/) für
deine Firma.

```
Windows:  (Administrator) wsl --install, neu starten
          winget install --id Docker.DockerDesktop -e
macOS:    brew install --cask docker-desktop
Linux:    curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker $USER
Prüfen:   docker --version  ·  docker compose version  ·  docker info
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
Prüfen:   ruff --version  ·  pytest --version
```

**ShellCheck** (script). Quelle: [shellcheck.net](https://www.shellcheck.net).

```
Windows:  winget install --id koalaman.shellcheck -e
macOS:    brew install shellcheck
Linux:    sudo apt install shellcheck
```

**PowerShell mit PSScriptAnalyzer** (script; das Skript installiert es immer mit, von Hand
genügt es, wenn das Repo `*.ps1` enthält).
Quellen: [PowerShell installieren](https://learn.microsoft.com/powershell/scripting/install/installing-powershell),
[PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview).

```
Windows:  Install-Module PSScriptAnalyzer -Scope CurrentUser     (in Windows PowerShell)
macOS:    brew install powershell, dann in pwsh dasselbe
Linux:    Paket powershell aus packages.microsoft.com, dann in pwsh dasselbe
```

---

## 6. Handgriffe

Das sind die Schritte, die kein Skript für dich tun kann oder darf. Das Skript nennt sie am
Ende einzeln (`HAND`); `--check` zählt sie als offen, bis sie erledigt sind.

### 6.1 Claude Code anmelden

`claude` in einem Terminal starten. Es öffnet den Browser; mit dem Konto aus Abschnitt 1
anmelden und zurück ins Terminal. Kontrolle: `claude auth status` zeigt `"loggedIn": true`.
Warum von Hand: Die Anmeldung gehört dir, sie läuft über deinen Browser und dein Konto.

### 6.2 GitHub anmelden

```
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
```

Der erste Befehl zeigt einen Code und öffnet github.com; dort Code eingeben und bestätigen.
Der zweite sorgt dafür, dass `git push` und `git clone` diese Anmeldung benutzen — ohne
eigene Passwörter oder SSH-Schlüssel. Kontrolle: `gh auth status`.
(Das Skript erledigt beides mit `-GitHubLogin`/`--github-login`.)

### 6.3 Git-Identität setzen

Jeder Commit trägt Name und Adresse. Nimm dieselbe Adresse wie im GitHub-Konto (oder die
`…@users.noreply.github.com`-Adresse aus GitHub → Settings → Emails):

```
git config --global user.name "Vorname Nachname"
git config --global user.email "du@firma.tld"
```

### 6.4 Tresor-Datei übernehmen

Geheimnisse (Zugänge zu Servern, API-Schlüssel, Datenbank-Passwörter) liegen bei uns in
KeePassXC — nie im Repository, nie in Chat, Mail oder Ticket.

1. Du bekommst von CoreVision eine eigene Datei `<name>.kdbx` mit den Einträgen deines Projekts.
   Das Master-Passwort kommt getrennt davon, auf einem zweiten Weg (Telefon, persönlich).
2. Datei nach `~/Tresor/` legen und in KeePassXC öffnen (Datenbank → Datenbank öffnen).
3. Werte, die ein Projekt braucht, trägst du in dessen `.env` ein (aus `.env.example`
   abgeleitet); `.env` bleibt lokal und ist in `.gitignore`.
4. Neue Geheimnisse, die du anlegst, meldest du CoreVision — die Firmen-Fassung pflegt
   CoreVision, nicht du.

### 6.5 Herd einmal starten (Windows, laravel/wordpress)

Nach der Installation Herd aus dem Startmenü öffnen. Herd richtet dabei PHP 8.4, Composer und
den Laravel-Installer ein und trägt sie in den PATH ein. In Herd unter „PHP“ Version 8.4
wählen. Danach eine **neue** PowerShell öffnen und `php -m` zeigt `intl`.

### 6.6 WSL2 und Docker Desktop (Windows)

Docker Desktop braucht WSL2. Fehlt es, meldet das Skript den Handgriff statt abzubrechen:

1. PowerShell **als Administrator** öffnen (Rechtsklick → „Als Administrator ausführen“).
2. `wsl --install` — installiert WSL2 und Ubuntu.
3. Rechner neu starten.
4. Das Einrichtungsskript erneut starten; jetzt kommt Docker Desktop.
5. Docker Desktop einmal öffnen, die Nutzungsbedingungen bestätigen. Eine Anmeldung bei
   Docker ist nicht nötig.

Unter macOS genügt Schritt 5. Unter Linux (ohne WSL) gilt die Gruppe `docker` erst nach
einmal Ab- und wieder Anmelden.

### 6.7 Rechte auf die Firmen-Repositories

Schicke CoreVision deinen GitHub-Benutzernamen. Du bekommst eine Einladung in die Organisation
`CoreVision-Systems-GmbH` per Mail bzw. unter [github.com/notifications](https://github.com/notifications);
annehmen. Kontrolle: `gh repo list CoreVision-Systems-GmbH` zeigt dein Projekt.

---

## 7. Erstes Projekt

```
gh repo clone CoreVision-Systems-GmbH/<projekt> ~/Code/<projekt>
cd ~/Code/<projekt>
claude
```

Beim ersten Start fragt Claude Code, ob du dem Ordner und dem Marketplace `corevision`
vertraust — ja. Danach meldet es:
„Firmenstandard coding-standard@corevision gilt in diesem Repo (Stack erkannt: …)“ und liest
Kern und Stack-Regeln. `/context` zeigt, was geladen ist.

Die Befehle des Projekts stehen in seiner `CLAUDE.md` unter „Befehle“. Erste Schritte meist:
Abhängigkeiten installieren (`composer install` und `npm ci` bei Laravel, `composer install`
bei WordPress, `npm ci` bei Astro, `python -m venv .venv` und
`pip install -r requirements-dev.txt` bei FastAPI), `.env` aus `.env.example` ableiten und aus
dem Tresor befüllen, dann einmal alle Prüfungen. **Erst wenn sie auf dem unveränderten Stand
grün sind, beginnt die Arbeit.**

---

## 8. Kontrolle

```
Windows:      & ([scriptblock]::Create((irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1))) -Check -Stack laravel
macOS/Linux:  curl -fsSL https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.sh | bash -s -- --check --stack laravel
```

Geprüft wird: Grundausstattung und Fassungen, die beiden Ordner, Plugin geladen und
automatische Aktualisierung an, Claude Code und `gh` angemeldet, Git-Identität, und je
gewähltem Stack die Werkzeuge samt Mindestfassung (PHP 8.4 mit `intl`, Node 22.12, Python 3.12
mit dem Befehl `python`, Docker läuft). Exit 0 und „Das Gerät erfüllt den Standard“ heißt:
fertig. Sonst ist der Exit-Code die Zahl der offenen Punkte.

---

## 9. Aktualisieren

### 9.1 Der Standard — automatisch

Jede neue Fassung des Standards erscheint als Release im Repository
[`CoreVision-Systems-GmbH/coding-plugins`](https://github.com/CoreVision-Systems-GmbH/coding-plugins).
Mit eingeschalteter automatischer Aktualisierung holt Claude Code sie **beim Start einer
Session** selbst; sie gilt ab der **nächsten** Session. Du musst nichts tun.

Eingeschaltet wird sie über den Eintrag `autoUpdate` in `~/.claude/settings.json` — das
Einrichtungsskript setzt ihn:

```json
"extraKnownMarketplaces": {
  "corevision": {
    "source": { "source": "github", "repo": "CoreVision-Systems-GmbH/coding-plugins" },
    "autoUpdate": true
  }
}
```

Von Hand geht es auch in Claude Code: `/plugin` → Marketplaces → `corevision` →
„Enable auto-update“. Projekte, die den Standard erklären, bringen denselben Eintrag in ihrer
`.claude/settings.json` mit.

Achtung: `claude plugin marketplace add` schreibt den Eintrag neu und verliert dabei
`autoUpdate`. Wer den Marketplace von Hand neu hinzufügt, schaltet danach die automatische
Aktualisierung wieder ein (oder startet das Einrichtungsskript erneut).

Sofort statt beim nächsten Start:

```
claude plugin marketplace update corevision
claude plugin update coding-standard@corevision
```

Welche Fassung du hast: `claude plugin list`. Was sich geändert hat: `plugins/coding-standard/CHANGES.md`.

### 9.2 Claude Code — automatisch

Der native Installer aktualisiert Claude Code im Hintergrund. Nichts zu tun.

### 9.3 Die Werkzeuge

Werkzeuge aktualisiert dein Paketmanager, nicht der Standard:

```
Windows:  winget upgrade --all
macOS:    brew update && brew upgrade
Linux:    sudo apt update && sudo apt upgrade
```

Ändert der Standard eine Fassung (etwa PHP 8.5), steht das in `CHANGES.md`. Das
Einrichtungsskript tauscht vorhandene Werkzeuge nicht aus — `--check` meldet die alte Fassung,
aktualisiert wird über den Paketmanager bzw. nach Weg B.

---

## 10. Fehlerbilder

| Zeichen | Ursache | Abhilfe |
|---|---|---|
| Filament-Tests enden mit HTTP 500, `php -m` ohne `intl` | Im PATH steht eine PHP-Fassung ohne `intl` — unter Windows oft die „herd-lite“-Fassung | Herd öffnen, PHP 8.4 wählen, neue Shell; `php -m` muss `intl` zeigen |
| `python` öffnet den Microsoft Store | Der App-Ausführungsalias von Windows verdeckt das echte Python | Einstellungen → Apps → Erweiterte App-Einstellungen → App-Ausführungsaliase: `python.exe` und `python3.exe` aus |
| „nicht im Pfad“ direkt nach der Installation | Die laufende Shell kennt neue Programme noch nicht | Neue Shell öffnen, Skript erneut starten |
| `irm … \| iex` bricht mit „Unerwartetes Attribut CmdletBinding“ ab | Das Skript wurde mit BOM gespeichert (nur bei lokal bearbeiteten Kopien) | Original-URL verwenden |
| `docker: permission denied` unter Linux | Gruppe `docker` gilt erst nach neuer Anmeldung | Ab- und wieder anmelden |
| Docker Desktop startet nicht, „WSL 2 installation is incomplete“ | WSL2 fehlt oder ist veraltet | Handgriff 6.6; `wsl --update` als Administrator |
| Beim Start kein Hinweis „Firmenstandard … gilt“ | Ordner nicht vertraut, oder das Projekt erklärt den Standard nicht | Claude Code im Projektordner neu starten und vertrauen; sonst CoreVision fragen |
| `claude plugin install` findet das Plugin nicht | Marketplace-Kopie veraltet | `claude plugin marketplace update corevision` |
| Das Skript bricht unter Git Bash ab | `setup.sh` ist nicht für Windows | `setup.ps1` in der PowerShell verwenden |

Hilft nichts davon: Ausgabe des Skripts und von `--check` kopieren und als Issue in
[`coding-plugins`](https://github.com/CoreVision-Systems-GmbH/coding-plugins/issues) melden.

---

## 11. Rückweg

Den Standard entfernen:

```
claude plugin uninstall coding-standard@corevision
claude plugin marketplace remove corevision
```

Die Sicherung `~/.claude/settings.json.bak-setup` enthält den Stand vor dem ersten Lauf. Die
Werkzeuge entfernst du mit `winget uninstall --id <Id>`, `brew uninstall <paket>` bzw.
`sudo apt remove <paket>`; die PATH-Zeilen stehen am Ende von `~/.zshrc` bzw. `~/.bashrc`
unter `# Augmented Coding (setup.sh)`. `~/Code` und `~/Tresor` löscht das Skript nie — das
entscheidest du.
