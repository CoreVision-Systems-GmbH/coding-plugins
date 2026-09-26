# coding-plugins — Augmented Coding bei CoreVision Systems

Hier liegt der Arbeits- und Qualitätsstandard „Augmented Coding“ von CoreVision Systems GmbH
in der Form, in der Werkzeuge ihn laden: heute als Plugin für Claude Code,
künftig auch für verwandte Werkzeuge. Dieses Repository ist die **Verteilstelle** — es wird
bei jedem Release aus dem internen Entwicklungs-Repository befüllt und nicht von Hand
bearbeitet.

Was der Standard bedeutet und warum, steht im Handbuch Augmented Coding, das Mitarbeiter
und Partner als PDF bekommen.

## Einrichtung in einem Lauf

Arbeitsplatz, Dev-Server und Prod-Server richtest du nach **[EINRICHTUNG.md](EINRICHTUNG.md)**
ein: das Kochbuch mit Skript und Handweg, Verzeichnisstruktur, Werkzeugen samt Quellen, den
Handgriffen, dem Server-Aufbau mit Edge-Caddy und DNS-01 und dem Rollout. Kurzfassung für den
Arbeitsplatz (Teil A):

**Windows**, in einer PowerShell:

```
irm https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.ps1 | iex
```

**macOS, Linux, WSL:**

```
curl -fsSL https://raw.githubusercontent.com/CoreVision-Systems-GmbH/coding-plugins/main/setup/setup.sh | bash
```

Das installiert die Grundausstattung (Git, GitHub CLI, Claude Code, KeePassXC, Plugin mit
automatischer Aktualisierung) und für die Arbeit auf dem Dev-Server Tailscale, VS Code mit
Remote-SSH und einen SSH-Schlüssel. Stack-Werkzeuge mit `-Stack <name>` bzw. `--stack <name>`,
die Kontrolle mit `-Check` bzw. `--check` — Einzelheiten in EINRICHTUNG.md, A.4.
Server: `plugins/coding-standard/server/setup-server.sh` (EINRICHTUNG.md, Teile B und C).
Quelle: [`setup/`](setup/).

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

Neue Fassungen erscheinen als Release in diesem Repository. Mit automatischer
Aktualisierung (setzt das Einrichtungsskript; in unseren Projekten ohnehin an) holt Claude
Code sie im Lauf einer Session selbst; sie gilt ab der nächsten — Einzelheiten in
EINRICHTUNG.md, A.9. Von Hand geht es so, danach Claude Code neu starten:

```
claude plugin marketplace update corevision
claude plugin update coding-standard@corevision --scope user
```

Scheitert der zweite Befehl, weil der Standard nur aus einem geklonten Projekt kommt: einmal
`claude plugin install coding-standard@corevision --scope user`.

## Inhalt

| Pfad | Was es ist |
|---|---|
| `.claude-plugin/marketplace.json` | Der Marketplace `corevision` |
| `plugins/coding-standard/` | Das Plugin: Kern, Stack-Overlays, Skills (`/projekt-neu`, `/projekt-aufnehmen`, `/release`, `/deploy-check`, `/rollout`, `/pr`), Hooks, Reviewer-Agents, Vorlagen |
| `plugins/coding-standard/server/` | Server-Baustein: `setup-server.sh`, `edge-site`, `rollout`, Edge-Caddy mit DNS-Modulen |
| `plugins/coding-standard/CHANGES.md` | Was sich je Fassung geändert hat |
| `EINRICHTUNG.md` | Kochbuch: Arbeitsplatz, Dev-Server, Prod-Server, DNS, Rollout — per Skript oder von Hand |
| `setup/` | Einrichtungsskripte für Windows (`setup.ps1`) und macOS/Linux/WSL (`setup.sh`) |

## Rückmeldungen

Änderungswünsche und Fehler bitte als Issue in diesem Repository. Pull Requests werden hier
nicht angenommen — der Inhalt entsteht im internen Repository und wird per Release
hierher veröffentlicht.

## Rechte

Siehe [LICENSE](LICENSE): Nutzung in Projekten von CoreVision Systems GmbH sowie
deren Auftragnehmern und Partnern; alle weiteren Rechte vorbehalten.
