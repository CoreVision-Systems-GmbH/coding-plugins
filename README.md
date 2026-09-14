# coding-plugins — Augmented Coding bei CoreVision Systems und PCN

Hier liegt der Arbeits- und Qualitätsstandard „Augmented Coding“ von CoreVision Systems GmbH
und PCN GmbH in der Form, in der Werkzeuge ihn laden: heute als Plugin für Claude Code,
künftig auch für verwandte Werkzeuge. Dieses Repository ist die **Verteilstelle** — es wird
bei jedem Release aus dem internen Entwicklungs-Repository befüllt und nicht von Hand
bearbeitet.

Was der Standard bedeutet und warum, steht im Handbuch Augmented Coding, das Mitarbeiter
und Partner als PDF bekommen.

## Einrichtung in einem Lauf

Das Einrichtungsskript installiert Git, die GitHub CLI und Claude Code, fügt den Marketplace
hinzu, installiert das Plugin und prüft alles. Schon Vorhandenes überspringt es. Kein
Administrator nötig.

**Windows**, in einer PowerShell:

```
irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1 | iex
```

**macOS, Linux, WSL:**

```
curl -fsSL https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.sh | bash
```

Danach eine neue Shell öffnen, `claude` starten und im Browser anmelden (Pro-, Max-, Team-
oder Console-Konto; der kostenlose Claude-Tarif enthält Claude Code nicht). Wer die
GitHub-Anmeldung gleich mit erledigen will: Windows
`& ([scriptblock]::Create((irm …/setup.ps1))) -GitHubLogin`, sonst `… | bash -s -- --github-login`.
Mit `-DryRun` bzw. `--dry-run` zeigt das Skript nur, was es tun würde. Quelle: [`setup/`](setup/).

## Installieren von Hand (Claude Code)

Voraussetzung ist ein installiertes Claude Code. Ein GitHub-Konto ist zum Installieren
nicht nötig.

```
claude plugin marketplace add CoreVision-Systems-GmbH/coding-plugins
claude plugin install coding-standard@corevision --scope user
```

Danach Claude Code neu starten. In einem Projekt, das den Standard erklärt (Datei
`.coding-standard` oder Eintrag in `.claude/settings.json`), lädt er sich beim Start von
selbst; Claude meldet „Firmenstandard coding-standard@corevision gilt in diesem Repo“.
Wer ein Projekt von uns klont und dem Ordner vertraut, bekommt Marketplace und Plugin
automatisch — die beiden Befehle oben sind dann nicht nötig.

## Aktualisieren

Neue Fassungen erscheinen als Release in diesem Repository. In unseren Projekten holt
Claude Code sie nach dem Sessionstart selbst; von Hand geht es so:

```
claude plugin marketplace update corevision
claude plugin update coding-standard@corevision
```

## Inhalt

| Pfad | Was es ist |
|---|---|
| `.claude-plugin/marketplace.json` | Der Marketplace `corevision` |
| `plugins/coding-standard/` | Das Plugin: Kern, Stack-Overlays, Skills (`/projekt-neu`, `/release`, `/deploy-check`, `/pr`), Hooks, Reviewer-Agents, Vorlagen |
| `plugins/coding-standard/CHANGES.md` | Was sich je Fassung geändert hat |
| `setup/` | Einrichtungsskripte für Windows (`setup.ps1`) und macOS/Linux/WSL (`setup.sh`) |

## Rückmeldungen

Änderungswünsche und Fehler bitte als Issue in diesem Repository. Pull Requests werden hier
nicht angenommen — der Inhalt entsteht im internen Repository und wird per Release
hierher veröffentlicht.

## Rechte

Siehe [LICENSE](LICENSE): Nutzung in Projekten von CoreVision Systems und PCN GmbH sowie
deren Auftragnehmern und Partnern; alle weiteren Rechte vorbehalten.
