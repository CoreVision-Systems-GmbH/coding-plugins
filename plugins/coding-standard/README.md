# coding-standard

Das Firmen-Plugin von PCN GmbH und CoreVision Systems für Claude Code. Es bringt den
Arbeitsstandard, die Stack-Regeln, die wiederkehrenden Abläufe, ein Geländer gegen
zerstörende Git-Befehle und die Reviewer-Agents mit.

Installation und Einrichtung: siehe [README des Repos](../../README.md).

## So wirkt der Standard — automatisch

Der Standard besteht aus zwei Textschichten, die **ohne Aufruf** in jede Session kommen,
sobald ein Repo ihn erklärt:

| Schicht | Datei | Umfang | Inhalt |
|---|---|---|---|
| **Kern** | `core/kern.md` | ≈ 50 Zeilen | Wie wir arbeiten, unabhängig vom Stack: Denken vor Code, Umsetzen, Beweis statt Behauptung, Git & Lieferung, Doku & Kontext, Definition of Done. Kein Framework-Wort. |
| **Stack-Overlay** | `stacks/<stack>.md` | ≤ 120 Zeilen | Firmenentscheidungen für einen Stack: Zuständigkeiten & Architektur, Grenzen, Werkzeugkette, Betriebsvertrag, stack-typische Fallen. Heute `laravel.md`, `fastapi.md`, `script.md` und `astro.md`, dazu `nextjs.md` als Ausnahme-Overlay für den Bestand; `_vorlage.md` für neue Stacks. |

**Erklärt** ist ein Repo, wenn `coding-standard@corevision` in seiner `.claude/settings.json`
steht (die Vorlage `templates/repo/.claude/settings.json` bringt das mit) oder eine
Markerdatei `.coding-standard` im Projektwurzelverzeichnis liegt. Dann läuft bei jedem
Session-Start, Resume, `/clear` und nach jeder Kompaktierung der Hook
`hooks/standard-context.sh`: Er erkennt den Stack an Markerdateien und weist Claude an,
Kern und passende Overlays **noch in der ersten Antwort mit dem Read-Tool zu lesen**; die
harten Regeln stehen zusätzlich in Kurzform direkt in der Hook-Ausgabe.

Warum nicht der Volltext im Hook: Claude Code blendet Hook-Ausgaben über rund 2 KB nur als
Vorschau ein und lagert den Rest aus — Kern plus Overlay sind 10–15 KB. Der Zeiger bleibt
unter 1,8 KB (im Test abgesichert); das Lesen kostet einen Werkzeugaufruf pro Session.

| Marker | Overlay |
|---|---|
| `composer.json` mit `laravel/framework` | `laravel.md` |
| `requirements*.txt` oder `pyproject.toml` mit `fastapi` | `fastapi.md` |
| `package.json` mit `astro` | `astro.md` |
| `package.json` mit `next` | `nextjs.md` (Ausnahme mit Auflagen — kein Stack für `/projekt-neu`) |
| `.coding-standard` mit einer Zeile `stack: <name>` | `<name>.md` |

Die letzte Zeile ist für Stacks ohne eigene Markerdatei — `script` erkennt man an nichts,
also nennt sich das Projekt selbst. Mehrere Treffer laden mehrere Overlays, doppelte werden
zusammengefasst. Nicht erklärte Verzeichnisse (Vault, Doku-Repos, fremde Projekte) bekommen
nichts. Notausgang für eine Session: `CODING_STANDARD_OFF=1`. Was geladen wurde, zeigt
`/context`.

## Neues Projekt: `/projekt-neu`

Der Skill `skills/projekt-neu/` führt ein gebündeltes Interview (Name, Zweck, Stack,
Firma/Eigentümer, Kunde) und ruft danach `scripts/projekt-neu.sh` auf. Das Skript ist
deterministisch und fragt nichts nach:

```bash
bash scripts/projekt-neu.sh --list-stacks
bash scripts/projekt-neu.sh --name <kebab> --stack <name> --owner <owner> \
     --purpose "<Zweck>" [--customer …] [--company …] [--dir …] [--no-github] [--vault …]
```

Ablauf: prüfen (Name, Stack, Werkzeuge aus `REQUIRES`, leerer Zielordner, `gh`-Anmeldung) →
`scaffold.sh` mit `PHASE=geruest` → gemeinsame und Stack-Vorlagen kopieren, Platzhalter
ersetzen → `scaffold.sh` mit `PHASE=einrichten` (Abhängigkeiten, erste Prüfung) →
`git init -b main` und ein Commit → `gh repo create --private --push` → Vault-Seite und
Daily-Log-Zeile → Abschlussbericht mit den offenen Handgriffen.

### Stack-Wahl

| Vorhaben | Stack |
|---|---|
| datennah — Datenmodell, Rechte, Verwaltung, Nutzerkonten, Formulare mit Serverlogik | `laravel` (das Arbeitspferd; im Zweifel dieser) |
| Dienst mit JSON-Schnittstelle ohne eigene Oberfläche | `fastapi` |
| Werkzeug ohne Laufzeit — Wartungslauf, Auswertung, Server-Handgriff | `script` |
| öffentliche Content-Site — Firmenseite, Landingpages, Doku, Blog | `astro` |

Innerhalb von `laravel` entscheidet das Overlay die Fläche: Filament für interne Verwaltung,
Inertia + React nur bei mindestens zwei von vier Kriterien (Client-State, unverzichtbare
npm-Bibliothek, öffentliches Marken-UI, gesicherte React-Kompetenz), öffentliche Seiten mit
SSR. **Next.js** ist kein Stack, sondern eine Ausnahme mit drei Bedingungen und Auflagen
(`stacks/nextjs.md`) — `/projekt-neu` bietet ihn nicht an. Auffindbarkeit und Ladezeit sind
kein Grund für ein Framework: messbar ist nur vollständiges HTML beim ersten Byte, und das
liefern Astro, Blade mit Cache und Inertia SSR genauso.

### Aufbau eines Stacks

```text
stacks/<name>.md              Overlay — die Regeln, geladen vom SessionStart-Hook
templates/<name>/stack.conf   Register: LABEL DESCRIPTION REQUIRES CONTAINERIZED MARKER
templates/<name>/befehle.md   Befehlsblock für die CLAUDE.md des Projekts ({{COMMANDS}})
templates/<name>/scaffold.sh  optional: Installer und Einrichtung, zweimal aufgerufen
templates/<name>/dateien/     alles, was ins Projekt kopiert wird
templates/repo/               gemeinsam für alle Stacks
templates/_vorlage/           Kopiervorlage für einen neuen Stack
```

**Neuen Stack anlegen:** `stacks/_vorlage.md` → `stacks/<name>.md` ausfüllen;
`templates/_vorlage/` → `templates/<name>/` ausfüllen; Erkennung entweder als Zeile in
`hooks/standard-context.sh` oder über `MARKER=1`; je einen Fall in
`hooks/test-standard-context.sh` und `scripts/test-projekt-neu.sh`; bei Bedarf einen dünnen
Skill `skills/<name>/SKILL.md` nach dem Muster von `skills/fastapi/`.

## Skills

Alle Skills sind auf `disable-model-invocation: true` gesetzt — Claude zieht sie **nicht**
von selbst heran. Sie werden ausschließlich vom Menschen aufgerufen.

| Skill | Aufruf | Zweck |
|---|---|---|
| `projekt-neu` | `/projekt-neu [name]` | Neues Projekt nach Firmenstandard: ein gebündeltes Interview, dann `scripts/projekt-neu.sh` (Gerüst, Vorlagen, Repo, Vault), bei Laravel die Firmenstandard-Nacharbeit, zum Schluss die offenen Handgriffe. |
| `coding` | `/coding [Aufgabe]` | Kern und Overlay **von Hand** laden und die Startroutine fahren (`CLAUDE.md`, `CHANGES.md`, `docs/status.md`, letzte Commits, offene PRs). Nötig nur in Sessions ohne automatische Aktivierung (Cowork, Repo ohne Erklärung) oder zum bewussten Nachladen. |
| `laravel` | `/laravel [Aufgabe]` | Stack-Overlay Laravel von Hand laden, Fassungen feststellen, UI-Flächen-Entscheid. |
| `fastapi` | `/fastapi [Aufgabe]` | Stack-Overlay FastAPI von Hand laden, Fassungen und Abweichungen feststellen. |
| `astro` | `/astro [Aufgabe]` | Stack-Overlay Astro von Hand laden, Fassungen und Abweichungen feststellen. |
| `release` | `/release [major\|minor\|patch\|X.Y.Z]` | Version aus den Commits vorschlagen, `CHANGES.md` abschließen, Release-PR durch die CI, Tag und GitHub-Release anlegen, Image-Referenz berichten. |
| `deploy-check` | `/deploy-check <kunde>/<produkt> <tag>` | Prüfliste vor dem Update einer Kundeninstanz: Ziel-Tag, Migrationen, ENV-Schlüssel, Drift, Sicherung, Gesundheit. Führt **kein** Update aus. |
| `pr` | `/pr [Hinweis]` | Draft-PR aus dem aktuellen Branch: Titel als Conventional Commit, Body nach der PR-Vorlage, CI-Status abrufen. Merged nicht. |

Rangfolge bei Widerspruch:

```text
ausdrückliche Anweisung des Nutzers
  > CLAUDE.md und .claude/rules/ des Repos
    > Stack-Overlay (stacks/*.md)
      > Kern (core/kern.md)
```

## Hook: git-guard

Ein `PreToolUse`-Hook auf dem Bash-Tool. Er liest den Befehlstext aus der Hook-Nutzlast
und blockiert zerstörende Befehle, bevor sie laufen. Ohne `jq` — unter Windows nicht
vorhanden — nur mit bash-Bordmitteln.

**Blockiert:**

| Befehl | Warum |
|---|---|
| `git push --force` / `-f`, Refspec mit `+` | Geschichte wird nicht überschrieben |
| `git push --force-with-lease` auf `main`/`master` | auf dem Hauptzweig auch nicht abgesichert |
| `git push origin main`, `-u origin main`, `origin HEAD:main`, `git push` während man auf `main` steht | der Weg auf `main` führt über einen PR |
| `git push --delete`, `git push origin :zweig` | Zweige räumt der gemergte PR auf |
| `git reset --hard` | verwirft nicht committete Arbeit |
| `git clean -f` / `-fd` / `-fdx` | löscht nicht verfolgte Dateien, oft auch `.env` |
| `git branch -D` | löscht auch ungemergte Zweige |
| `git checkout -- .` | verwirft alle Änderungen im Arbeitsbaum |
| `git restore .` / `git restore --staged .` | dito |
| `rm -rf` auf `/`, `/*`, `~`, `.`, `*`, `..` oder einen absoluten Pfad außerhalb des Arbeitsverzeichnisses | löscht mehr als gemeint |

**Bleibt erlaubt:** Tags pushen (`git push origin v1.2.3`, `git push --tags`), Push auf
einen Feature-Zweig, `--force-with-lease` auf dem eigenen Zweig, `git clean -n`,
`git branch -d`, gezieltes `git restore <datei>`, `rm -rf` auf einen relativen Pfad im
Projekt.

Der Ablehnungsgrund sagt jeweils, was stattdessen zu tun ist. Der Hook ist ein Geländer,
kein Gefängnis: er sieht den Befehlstext, nicht dessen Laufzeitverhalten. Er soll den
versehentlichen Griff verhindern.

**Ausnahme für Doku- und Backup-Repos:** Liegt im Arbeitsverzeichnis der Session eine Datei
`.git-guard-main-ok`, ist dort der Push auf `main`/`master` erlaubt — für Repos ohne
PR-Fluss wie einen Notiz-Vault, dessen Sicherung direkt auf `main` geht. Alles andere
(Force-Push, Löschen von Remote-Zweigen, `reset --hard`, `clean -f`, `branch -D`, `rm -rf`)
bleibt auch dort geblockt. Die Datei gehört ins Repo, damit die Ausnahme sichtbar ist; in
einem Code-Repo hat sie nichts verloren. Der Hook liest das `cwd` der Nutzlast, die Ausnahme
gilt also für die Session, nicht für einen per `cd` oder `-C` angesprochenen Fremdordner.

**Test:**

```bash
bash plugins/coding-standard/hooks/test-git-guard.sh
```

49 Fälle, blockiert und erlaubt. Der Lauf muss grün sein, bevor eine Änderung am Hook
committed wird. Neue Regel im Hook heißt: neuer Fall im Test.

## Agents

Sieben Reviewer. Alle lesen nur (`Read`, `Grep`, `Glob`, `Bash`) — Ausnahme `build-fixer`,
der zusätzlich `Edit` und `Write` darf. Alle laufen auf `model: inherit`.

| Agent | Einsatz |
|---|---|
| `reviewer` | Allgemeines Review vor „Ready for review". Prüft zusätzlich den Diff gegen Plan und PR-Text — Scope-Treue und „Nicht Teil davon". |
| `security-reviewer` | OWASP Top 10, Secrets, Autorisierungslücken, SSRF, Injection, unsichere Deserialisierung, Rate-Limiting. |
| `laravel-reviewer` | Policies und Gates serverseitig, Filament-Middleware-Stapel, N+1, Massenzuweisung, Validierung in Requests, additive Migrationen, `env()` nur in `config/`. |
| `database-reviewer` | Indizes, Transaktionen, Migrationsreihenfolge, expand/contract, PostgreSQL-Spezifika. |
| `python-reviewer` | Fehlerbehandlung, Typannotationen, Nebenläufigkeit, Ressourcen, die üblichen Python-Fallen. |
| `typescript-reviewer` | Typsicherheit, Async-Korrektheit, Fehlerbehandlung, React-Hooks, Server/Client-Grenzen. |
| `build-fixer` | Behebt Build-, Compiler- und Typfehler mit minimalem Diff. Kein Refactoring, kein Abschalten der Prüfung. |

Gemeinsames Ausgabeformat: eine Tabelle
`Datei:Zeile · Schwere · Befund · Beleg · Vorschlag`, danach ein Abschnitt
**„Nicht geprüft"**. Schweregrade CRITICAL / HIGH / MEDIUM / LOW. Regel für alle: nur
Korrektheit, Sicherheit und Scope-Treue; keine Stilfragen ohne Auftrag; jeder Befund
braucht einen Beleg.

## Aufbau

```text
plugins/coding-standard/
  .claude-plugin/plugin.json
  core/kern.md                    immer gültig, stack-unabhängig
  stacks/laravel.md               Overlay Laravel
  stacks/fastapi.md               Overlay FastAPI
  stacks/script.md                Overlay Skripte und Werkzeuge
  stacks/astro.md                 Overlay Astro (öffentliche Content-Sites)
  stacks/nextjs.md                Ausnahme-Overlay Next.js (Bestand)
  stacks/_vorlage.md              Vorlage für neue Stacks
  skills/projekt-neu/SKILL.md     neues Projekt nach Firmenstandard
  skills/coding/SKILL.md          manueller Schalter Kern + Overlay + Startroutine
  skills/laravel/SKILL.md         manueller Schalter Overlay Laravel
  skills/fastapi/SKILL.md         manueller Schalter Overlay FastAPI
  skills/astro/SKILL.md           manueller Schalter Overlay Astro
  skills/release/SKILL.md
  skills/deploy-check/SKILL.md
  skills/pr/SKILL.md
  scripts/projekt-neu.sh          Bootstrap eines neuen Projekts
  scripts/test-projekt-neu.sh
  hooks/hooks.json                SessionStart → standard-context.sh, PreToolUse → git-guard.sh
  hooks/standard-context.sh       lädt Kern + Overlays automatisch
  hooks/test-standard-context.sh
  hooks/git-guard.sh
  hooks/test-git-guard.sh
  agents/*.md
  templates/repo/                 gemeinsame Projektvorlagen
  templates/laravel|fastapi|script|astro/   Stack-Register, Gerüst, Dateien
  templates/_vorlage/             Kopiervorlage für einen neuen Stack
  templates/pull_request_template.md  PR-Vorlage dieses Repos
  CHANGES.md
```

Tests vor jedem Commit an Hooks oder Bootstrap:

```bash
bash plugins/coding-standard/hooks/test-standard-context.sh
bash plugins/coding-standard/hooks/test-git-guard.sh
bash plugins/coding-standard/scripts/test-projekt-neu.sh
```
