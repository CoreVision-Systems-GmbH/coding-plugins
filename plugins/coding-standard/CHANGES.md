# Änderungen

Alle nennenswerten Änderungen an diesem Plugin stehen hier.

Das Format folgt [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), die
Versionierung [Semantic Versioning](https://semver.org/lang/de/).

## Unveröffentlicht

## [1.1.0] — 2026-09-25

### Hinzugefügt

- **Editor-Dateien je Stack** (`.vscode/settings.json`, `extensions.json`, `tasks.json` in allen
  Vorlagen): derselbe Schutz für den Menschen im Editor wie für Claude durch den Git-Guard —
  kein „alles stagen“ (`git.enableSmartCommit` aus), `main` geschützt, Force-Push abgeschaltet,
  Zweigpräfix `feat/`, UTF-8 mit LF (PowerShell CRLF mit BOM), Rechtschreibung Deutsch und
  Englisch, Pint bzw. ruff beim Speichern, Ausschlüsse für `vendor`, `node_modules`, `.venv`.
  Die Tore als Aufgaben (Terminal → Aufgabe ausführen): `check` als Standard-Testaufgabe,
  Kennzahlen, Konfiguration, Lizenzen, Rauchtest-Trockenlauf, Dev-Instanz, Playwright, PR-Text.
  Empfohlene Erweiterungen je Stack (Claude Code, Remote-SSH, EditorConfig, Rechtschreibung,
  markdownlint, YAML, ShellCheck, Container Tools; PHP über Intelephense (kostenlos) mit
  Pint/PHPStan/Laravel/Playwright bzw. PHP Sniffer & Beautifier für die WordPress-Coding-Standards,
  Python/ruff/mypy, Astro, PowerShell) — ein zweiter PHP-Sprachserver ist als unerwünscht
  eingetragen (zwei nebeneinander fressen Gigabytes). Kein globales Profil: Die Dateien reisen mit
  dem Repo; `.gitignore` lässt nur diese drei aus `.vscode/` durch. `/projekt-aufnehmen`
  meldet und legt sie an (Stufe 1), nie überschreibend.

- **Lesesperren für Claude-Sessions auf dem ganzen Gerät:** Die Einrichtung (`setup.sh`,
  `setup.ps1`) trägt `permissions.deny` in `~/.claude/settings.json` ein — `.env` samt
  Varianten, `~/Tresor`, `~/.ssh`, private Schlüssel, Dumps. Bisher galt die Liste nur je
  Projekt aus der Vorlage; in einem Repo ohne erklärten Standard las Claude die `.env`.
  Vorhandene Einträge und die Erlaubnisliste bleiben, `--check` meldet fehlende Sperren.
- **`core.hooksPath` setzt sich beim Sessionstart:** Liegt der gitleaks-Hook der Vorlage allein in
  `.githooks/`, steht die Session an der Wurzel des Repos und ist nichts gesetzt (auch nicht
  global), trägt der SessionStart-Hook `core.hooksPath .githooks` ein und sagt es. Der Handgriff
  „einmal je Klon“ entfällt, sobald Claude Code einmal im Klon gestartet wurde; wer vorher im
  Terminal committet, setzt ihn von Hand. Eigene Hooks (husky, globaler `hooksPath`) bleiben
  unberührt, ein fremder `pre-commit` ohne gitleaks oder ein Ordner mit weiteren Hooks wird
  nicht aktiviert — ein fremdes Repo mit Marker schaltet beim Sessionstart nichts scharf.

### Geändert

- **Der Git-Guard hängt auch am PowerShell-Werkzeug.** Bisher galt er nur für das Bash-Werkzeug
  — ein `git push origin main` oder `Remove-Item -Recurse -Force ~` über PowerShell lief ohne
  Geländer durch (beim Release 1.0.0 selbst so passiert). Jetzt gelten dieselben Regeln in beiden
  Shells; dazu versteht der Hook `Remove-Item` samt Aliassen (`ri`, `rm`, `rd`, `del`),
  abgekürzte Parameter (`-r`, `-fo`), `-Path`, Kommalisten und Laufwerkspfade (`C:\`, `/c/`,
  `/mnt/c/`). Drei Umgehungen sind geschlossen: JSON-Unicode-Maskierung (`m\u0061in` war ein
  `m?in`), Zeilenfortsetzung (`\` oder `` ` `` am Zeilenende trennte den Befehl) und
  `Git.exe` in Großschreibung. 63 neue Testfälle (183 gesamt). Die Ausnahme
  `.git-guard-main-ok` gilt in beiden Shells.

## [1.0.0] — 2026-09-25

### Hinzugefügt

- **Kennzahlen je Funktion** (`scripts/komplexitaet-pruefen.sh` in allen fünf Stacks, Teil von
  `check` und der CI): Komplexität ≤ 10, ≤ 50 Anweisungen, ≤ 12 Verzweigungen — ruff (`C901`,
  `PLR0912`, `PLR0915`), PHPMD (`phpmd.xml`, neu in Laravel und WordPress, dazu Methoden- und
  Klassenlänge), ESLint, wo es im Repo liegt (dazu Verschachtelung ≤ 4, Datei ≤ 800 Zeilen).
  Bis Ende 2026 eine Warnung, ab 2027-01-01 rot. Der Kern nennt die Zahlen.
- **Laravel:** `pint.json` mit `declare_strict_types` und Import-Regeln, `rector.php` mit
  monatlichem Probelauf (`monatlich.yml`, zeigt nur an), `php artisan view:cache` in `check`
  (übersetzt jede Blade-Vorlage), `phpunit.xml` nagelt die Suite mit `force="true"` auf SQLite
  fest — alles über die Nacharbeit-Checkliste von `/projekt-neu`.
- **Testregeln** (`tests.md` aller Stacks): Kreuzprobe bei Mandanten (Abweisung, nicht leere
  Liste; Filter zentral am Modell), synthetische Testdaten (`de_AT`, `example.org`, nie ein
  Produktionsauszug), Regressionsliste mit Vorfall und Fassung im Testnamen, Grenzwerte selbst
  testen. `/projekt-aufnehmen`: Statik im Bestand über eine datierte Baseline mit Abbauplan —
  jede angefasste Datei verlässt sie; neuer Code läuft nie gegen die Baseline.

- **Konfigurations- und Lizenzprüfung** in allen Container-Stacks (`scripts/konfig-pruefen.sh`,
  `scripts/lizenzen-pruefen.sh`), Teil von `check` und der CI: Geheimnisse haben in `.env.example`
  keinen Wert, Debug ist aus, production ist die Vorgabe, im öffentlichen Ordner liegt nur
  `index.php`, keine Debug-Werkzeuge in `require`, nichts Vertrauliches im Repo; Lizenzen der
  ausgelieferten Abhängigkeiten gegen eine Allow-Liste — Copyleft ist ein Befund (WordPress darf
  GPL), LGPL/MPL und Unbekanntes eine Warnung, Ausnahmen mit Grund in
  `docs/lizenzen-ausnahmen.txt`. `deploy/update.sh` bricht ab, wenn die `.env` der Instanz nicht
  production/Debug aus trägt. Die ADR-Vorlage fragt nach der Lizenz neuer Abhängigkeiten;
  `/projekt-aufnehmen` meldet fehlende Skripte.

- **Diff-Abdeckung und Nachtprüfung** (Laravel, FastAPI): Die CI misst bei jedem PR die
  Abdeckung der neuen und geänderten Zeilen (diff-cover, Schwelle 80 %) — bis Ende 2026
  eine Warnung, ab 2027-01-01 rot; der Bestand wird nicht gemessen. `nightly.yml` fährt den
  Mutationstest (`pest --mutate` bzw. `mutmut`, Schwelle 60) und bei Laravel Wanderungen und
  Suite gegen PostgreSQL 18 (der Standardlauf bleibt SQLite im Speicher); Befunde sind WARN
  mit Termin in `docs/status.md`, kein Tor. `/projekt-aufnehmen` meldet beides, wenn es fehlt.

- **Browser-Prüfung mit Playwright** (`tests/e2e/` in den Vorlagen Laravel und Astro, Script
  `npm run e2e`): drei Viewports (Desktop, Tablet, Handy), `smoke.spec.ts` liest dieselbe Liste
  wie der Rauchtest (`deploy/smoke.txt`) und prüft dazu Konsolenfehler und gescheiterte
  Anfragen, `sweep.spec.ts` folgt jedem internen Link der Startseite; `retries: 0`, nachts
  `E2E_REPEAT=2` zur Flaky-Erkennung, JSON-Ergebnis. Läuft gegen die Dev-Instanz aus dem
  Tailnet, nicht in der GitHub-CI. Regeln in `.claude/rules/tests.md` (Astro neu, Laravel
  ergänzt); Laravel bekommt Paket und Script über die Nacharbeit-Checkliste.

- **Die CI prüft den PR-Text** (`scripts/pr-text-pruefen.sh`, Schritt „PR-Text prüfen“ im
  Auftrag `ci` aller Stacks und dieses Repos): Abnahmekriterien mit Nachweis, ein Prüfweg mit
  Ergebnis, „Nicht geprüft“ und „Rückweg“ müssen gefüllt sein — sonst ist der PR rot. Der
  Schritt liest den aktuellen Text über `gh`; ein erneuter Lauf nach einer Textänderung zählt.
  Dependabot ist ausgenommen. `/projekt-neu` liefert Prüfer und Schritt mit, `/projekt-aufnehmen`
  meldet den fehlenden Schritt. Lokal: `gh pr view <nr> --json body -q .body | bash
  scripts/pr-text-pruefen.sh`.
- **Prüfprotokoll in der PR-Vorlage** — Pflicht bei Rechten, Schema, Mandanten, Anmeldung,
  Geld oder Kundenauslieferung: Soll/Ist je Anforderung mit Beleg, Befunde mit Schwere und
  Frist, bewusst nicht Getanes, Gegenprüfung, Urteil FREIGEGEBEN / BEDINGT / GESPERRT. `/pr`
  füllt es, der `reviewer` verlangt es auf diesen Pfaden.

- **Rauchtest nach jedem Start** (`deploy/smoke.txt` + `deploy/smoke.sh` in allen vier
  Container-Stacks): Routen mit erwartetem Status, Zeitbudget und Pflichtinhalt. `deploy/dev.sh
  up` warnt bei Rot, `deploy/update.sh` bricht mit Rückweg ab. Impressum (UID) und Datenschutz
  (Verantwortlicher) stehen bei Astro und WordPress in der Liste — leer geht die Site nicht
  online; das Astro-Gerüst liefert beide Seiten als Platzhalter. `/projekt-aufnehmen` meldet
  fehlende Rauchtest-Dateien.
- **Mailpit in der Laravel-Dev-Instanz** (`compose.dev.yaml`, Dienst `mail`): jede Mail landet
  dort, keine bei echten Empfängern; Oberfläche auf Port 8025 der Tailscale-IP des Dev-Servers
  (`DEV_BIND_IP` aus `server.env`, sonst 127.0.0.1 — nie 0.0.0.0, Docker umgeht ufw).
- **Datenjobs** als Abschnitt 6 in den Overlays Laravel und FastAPI: Trockenlauf als Vorgabe,
  `--apply` schreibt, idempotent, Mengenabgleich vorher/nachher, `--check` mit Exit ≠ 0 bei
  Drift, Blöcke mit Wiederaufnahme. Der `database-reviewer` verlangt es seit 0.10.0.
- **Einwilligung nur, wenn es etwas einzuwilligen gibt** (Overlays Astro und WordPress): kein
  Consent-Banner ohne Tracker; mit Trackern lädt nichts vor dem Opt-in.

- **Ein Prüfbefehl je Stack:** `composer check` (Laravel, WordPress), `npm run check` (Astro:
  Typen, Bau, Tests) und `bash scripts/check.sh` (FastAPI, Script). Die `CLAUDE.md` neuer
  Projekte nennt ihn als erste Zeile unter „Befehle“, die CI führt dieselben Schritte aus;
  `/projekt-aufnehmen` meldet, wenn er in einem bestehenden Repo fehlt. Der Kern verlangt ihn
  vor jedem Commit.

- **Geheimnis-Scanner gitleaks** auf drei Ebenen, damit Zugangsdaten nicht ins Repo kommen
  (Fehlermuster H):
  - **CI:** Der Schritt „Geheimnisse (gitleaks)“ in `tests.yml` aller Stacks prüft direkt
    nach dem Checkout den Arbeitsbaum und bei einem PR jeden einzelnen Commit — gitleaks
    8.30.1 als Binary mit Prüfsumme aus dem Release, keine Marketplace-Action (die verlangt
    für Organisationen eine Lizenz). Jeder Treffer ist FAIL.
  - **Vor jedem Commit:** Der Hook `.githooks/pre-commit` prüft die vorgemerkten Änderungen.
    `/projekt-neu` und `/projekt-aufnehmen` legen ihn an, setzen `git config core.hooksPath
    .githooks` und das Ausführbar-Bit im Index. Fehlt gitleaks auf dem Gerät, warnt der Hook
    nur und lässt durch — die CI prüft trotzdem. Ein Befund wird behoben oder in
    `.gitleaks.toml` mit Grund erlaubt; `--no-verify` blockt der Git-Guard.
  - **Regeln in `.gitleaks.toml`:** die eingebauten Regeln von gitleaks plus zwei eigene, nur
    unter `tests/`: IBAN und E-Mail-Adressen mit echter Domäne (Testdaten sind synthetisch).
    Erlaubt sind `.env.example`, Platzhalter wie `<token>` und die Beispieldomänen
    `example.org`, `example.com`, `example.net`, `example.invalid`.
  - **Einrichtung:** gitleaks gehört zur Grundausstattung von `setup.sh` und `setup.ps1`
    (winget `Gitleaks.Gitleaks`, Homebrew, unter Linux das Binary 8.30.1 mit Prüfsumme nach
    `~/.local/bin`); `--check` meldet ihn, wenn er fehlt — auch auf dem Dev-Server.

  Bestehende Projekte: `.githooks/pre-commit` und `.gitleaks.toml` aus `templates/repo` sowie
  den CI-Schritt aus `templates/<stack>/dateien/.github/workflows/tests.yml` übernehmen, dann
  `git config core.hooksPath .githooks` — einmal je Klon, denn die Einstellung reist nicht mit.

- **Erlaubnis- und Sperrliste für Claude-Sessions** in der `.claude/settings.json` neuer
  Projekte (`permissions`): Die Prüfbefehle des Stacks (`composer check`, `npm run check`,
  `ruff`, `pytest`, `make check`, `git status|diff|log` …) laufen ohne Nachfrage. Gesperrt ist
  für das Read-Tool (und damit Edit, Write, Grep, Glob) das Lesen von `.env` samt `.env.local`,
  `.env.backup`, `.env.testing` und Co. in jeder Tiefe (`.env.example` bleibt frei — es ist
  das Schema), von `~/.ssh`, Tresor-Dateien (`*.kdbx`), privaten Schlüsseln und Dumps; für das
  Bash-Tool `git diff --no-index` (gäbe eine `.env` aus) und die Datenbanklöscher
  (`migrate:fresh|refresh|reset`, `db:wipe`, `alembic downgrade base`, `wp db reset|drop|clean`,
  dieselbe Liste wie im Git-Guard). `cat .env` im Bash-Tool bleibt eine Nachfrage — die Liste
  ist ein Geländer für die Werkzeuge, kein Ersatz für die Datenregel des Kerns.
  `/projekt-aufnehmen` meldet eine `settings.json` ohne `permissions` als Lücke und trägt sie
  in ADR und `docs/status.md` ein (die Datei wird nie überschrieben — die Liste aus
  `templates/repo/.claude/settings.json` von Hand übernehmen).

- **Sofortprüfung nach jedem Edit** (`hooks/edit-check.sh`, PostToolUse auf Edit, Write und
  MultiEdit): Die geänderte Datei wird auf Syntax und Format geprüft — `php -l` und Pint,
  `ruff check`/`ruff format --check`, `bash -n` und shellcheck, `node --check` und ESLint,
  JSON — und Befunde kommen als Zusatzkontext zurück, in Sekunden statt erst beim nächsten
  `check`. Der Hook ändert nichts und bricht nichts ab; er läuft nur in erklärten Repos und
  nur mit Werkzeugen, die im Repo oder im PATH vorhanden sind. Notausgang wie beim
  SessionStart-Hook: `CODING_STANDARD_OFF=1`.

### Geändert

- **Verbünde gehärtet** (`compose.yaml` aller vier Container-Stacks): Wurzeldateisystem
  schreibgeschützt (`read_only`, Schreibpfade als Volume oder tmpfs), `cap_drop: ALL` (Postgres
  und MariaDB holen sich die fünf zurück, die ihr Start braucht), `no-new-privileges`,
  Log-Rotation 5 × 20 MB je Container, Pflichtvariablen mit `:?` — fehlt `DB_PASSWORD` in der
  `.env`, startet der Verbund nicht, statt mit leerem Passwort loszulaufen. Laravel: Logs über
  `LOG_CHANNEL=stderr`, `public/storage` entsteht beim Bau des Abbilds. `/deploy-check` prüft
  die Härtung der laufenden Container (Punkt g), `/projekt-aufnehmen` meldet eine `compose.yaml`
  ohne Härtung. Bestehende Projekte übernehmen die `compose.yaml` aus `templates/<stack>/dateien`
  — beim nächsten Update, nach einem Probelauf auf der Dev-Instanz. Geheimnisse als Dateien
  (`*_FILE`, Compose `secrets:`) folgen, sobald eine Instanz zum Prüfen läuft.
- **Der Git-Guard blockiert mehr** — deshalb wird die nächste Fassung 1.0.0:
  - `git add` ohne Pfadangabe (`.`, `-A`, `--all`, `-u`, `:/`) — Dateien werden mit exaktem
    Pfad gestagt, damit `.env`, Dumps und Diagnoseskripte nicht im Repo landen (Fehlermuster
    F und H). `git commit -a` bleibt erlaubt: es nimmt nur bereits verfolgte Dateien mit. In
    Repos mit der Markerdatei `.git-guard-main-ok` (Doku, Backup) bleibt `git add -A` erlaubt.
  - `git commit --no-verify` / `-n`, `git push --no-verify`, das Setzen, Umbiegen oder
    Entfernen von `core.hooksPath` (auch `git config set|unset`, `-f <datei>`, `git -c`) —
    die Prüfhooks des Repos gelten; erlaubt bleiben das Lesen des Werts und
    `git config core.hooksPath .githooks`.
  - Datenbanklöscher: `php artisan migrate:fresh|refresh|reset`, `db:wipe`,
    `alembic downgrade base`, `wp db reset|drop|clean` — auch hinter `docker compose exec`,
    `uv run` oder `php -d …`. Nur der Nutzer führt sie aus, nach Blick auf die Datenbank-URL.
  Der Hook liest Anführungszeichen und Heredocs mit: `--no-verify` in einem Commit-Text oder
  `git add .` im Rumpf einer Commit-Nachricht sind Daten, kein Befehl.
  Der Kern nennt die beiden Git-Regeln unter „Git & Lieferung“.

## [0.10.0] — 2026-09-25

### Hinzugefügt

- **`CLAUDE.md` neuer Projekte** trägt die Zieldatenbank (`Datenbank: PostgreSQL 17` usw.,
  aus `stack.conf` je Stack — die KI soll keinen Dialekt raten), ein **Glossar** für
  deutsche Fachbegriffe in Bezeichnern (ASCII-Schreibweise für Code und Datenbank, Umlaut
  für die Oberfläche) und einen Abschnitt **„Bestätigte Schnittstellen“** für Spalten,
  Endpunkte und Befehle, die gegen das echte System geprüft wurden. `/projekt-aufnehmen`
  legt dieselbe `CLAUDE.md` an; ohne erkannten Stack steht bei der Datenbank „unbekannt —
  in CLAUDE.md eintragen“.
- **PR-Vorlage** (auch die Fallback-Vorlage des Skills `/pr`) mit Tabelle der
  Abnahmekriterien (A1…An, je mit Nachweis) und drei neuen Punkten in der Definition of Done:
  jedes Kriterium hat einen Nachweis; Review in frischem Kontext, bei Anmeldung, Rechten,
  Datenbank oder Mandanten auch der Sicherheits-Review; bei Rechten, Schema, Mandanten,
  Anmeldung, Geld oder KI-erzeugtem Bestand die Gegenprüfung durch ein zweites Modell oder
  einen zweiten Menschen.
- **`docs/status.md`** neuer und aufgenommener Projekte hat einen Abschnitt **„Rückstände“**
  — Befunde, die nicht sperren, mit Schweregrad, Termin und Quelle.

### Geändert

- **Der Kern ist neu geschrieben** (`core/kern.md`), nach dem Vergleich mit einem zweiten
  Coding-Standard und der Entscheidung, welche Regeln wir aufnehmen. Was neu gilt:
  - **Fünf Leitsätze** im Kopf: Denken vor Code · Bauen ist nicht prüfen · Beweis statt
    Behauptung · Nie direkt auf `main` · Ein Mensch gibt frei.
  - **Verbindlichkeitsgrade** muss / soll / kann; von einer Muss-Regel weicht nur eine ADR mit
    Freigabe ab. Widersprüche werden gemeldet, bis zur Entscheidung gilt die strengere Auslegung.
  - **Abnahmekriterien nummeriert (A1…An)** mit der Invariante, die erhalten bleiben muss; die
    Abschlusszeile „Geändert“ nennt sie.
  - **Baseline:** Vor der ersten Änderung laufen alle Prüfungen auf dem unveränderten Stand.
  - **Diagnose vor Reparatur:** Ursache am echten Verhalten nachweisen, dann Test, dann Fix;
    nach zwei Versuchen ohne Fortschritt den Auftrag prüfen. Charakterisierungstest vor Umbau.
  - **Selbstprüfung je Teilschritt** mit den vier Grenzfällen leer · sehr viele Datensätze ·
    Sonderzeichen und Umlaute · fehlende Berechtigung.
  - **Stopp-Weiche** erweitert um Architektur, Datenbankschema, Mandanten, Anmeldung, Rechte;
    Commit und Push auf den eigenen Zweig bleiben Routine.
  - **Neuer Abschnitt „Arbeiten mit KI“:** getrennte Rollen (die prüfende KI ändert nichts),
    Gegenprüfung durch ein zweites Modell oder einen zweiten Menschen bei Risiko, Datenregel
    (was an einen KI-Dienst darf), Gedächtnis nur für die Person, keine fremden Agent-Sammlungen
    ohne ADR, Kennzeichnung von KI-Funktionen im Produkt.
  - **Tests:** Kreuzprobe bei Mandanten (Abweisung, nicht leere Liste); „der Test einer
    Sicherung stellt die Gefahr her“. **Fristen** je Schweregrad und für Schwachstellen in
    Abhängigkeiten (Sicherheits-Bumps sofort). Rückstände mit Termin in `docs/status.md`.
  - **Geheimnisse:** in die Historie geraten → wechseln, nicht nur entfernen; Meldekultur.
  - **Nur der Server schützt:** Berechtigungen serverseitig, objektbezogen, bei Mandanten
    zentral am Modell.
  - **Bezeichner Englisch als Basis;** deutsche Fachbegriffe nur über das Glossar in `CLAUDE.md`.
  - **Git:** Der PR ist die Lieferung; ein Thema je PR, über etwa 400 Zeilen stapeln; der
    Commit-Rumpf nennt die verworfene Alternative; Code nie im Cloud-Sync.
  - **Definition of Done** beginnt mit „Ein Mensch gibt frei“ — Review-Pflicht 1 ab der
    zweiten Person, eigene Durchsicht bei Ein-Personen-Repos.
  Für bestehende Projekte ändert sich nichts an Dateien; die Regeln gelten ab der nächsten
  Session. Wer ein Glossar braucht, legt es in `CLAUDE.md` an (Vorlage folgt).
- **Die Reviewer-Agents prüfen die KI-Fehlermuster A–L** als Pflichtliste — fehlender
  Import, Aufruf nach geänderter Signatur, ungefilterte Ausgabe (auch in Berichtsgeneratoren),
  datenbankspezifisches SQL in Migrationen, erfundene Spalten und Schema-Drift, Diagnoseskripte
  im öffentlichen Verzeichnis, Konfiguration außerhalb der Konfiguration, eingecheckte
  Zugangsdaten, Test ohne Aussage, Fix statt Ursache, erfundener Projektbefehl, stiller
  Fehlerkanal — dazu die vier Pflicht-Grenzfälle (leer, sehr viele Datensätze, Sonderzeichen
  und Umlaute, fehlende Berechtigung), den Charakterisierungstest vor einem Umbau und das
  Abhaken der Abnahmekriterien A1…An. Die drei wichtigsten Befunde stehen zuoberst, jeder
  Schweregrad trägt seine Frist.
- **`security-reviewer` nach OWASP Top 10 in der Fassung 2025** (neue Kategorien Lieferkette
  und Fehlbehandlung von Ausnahmen; neuer Prüfpunkt Log-Injection) mit einer ASVS-5.0-Kurzliste
  für Authentifizierung (V6), Sitzung (V7) und Zugriff (V8), der Kopfzeilen-Falle (keine Vertrauensentscheidung aus `Host`, `Referer`,
  `X-Forwarded-For`) und der Sperrregel: ein bestätigter Befund bei Zugriffskontrolle,
  Injection oder Codeausführung sperrt, gleich wie grün alles andere ist.
- **`laravel-reviewer` und `database-reviewer`** verlangen den Mandantenfilter zentral am
  Modell und die Kreuzprobe (A liest B → Abweisung), lehnen rohes SQL und Treiberweichen in
  Migrationen ab, verlangen bei Datenjobs Trockenlauf, `--apply` und Mengenabgleich und bei
  neuen Spalten mit Personenbezug den Eintrag im Datenschutzverzeichnis mit Löschweg. Neue
  Laravel-Falle: `redirect()->back()` ohne Referer.
- `build-fixer` läuft auf `sonnet` — mechanische Arbeit, günstigeres Modell.

## [0.9.1] — 2026-09-23

### Behoben

- **`claude-review` war bei jedem Dependabot-PR rot.** Läufe von Dependabot bekommen nur
  Dependabot-Secrets, das Token für die Durchsicht blieb leer. Der Auftrag entfällt für diese
  PRs jetzt, wie schon ohne `CLAUDE_REVIEW_ENABLED`. Bestehende Projekte übernehmen die Zeile
  `if:` aus `templates/repo/.github/workflows/claude-review.yml` von Hand.

## [0.9.0] — 2026-09-23

### Hinzugefügt

- **Server-Baustein `server/`** für Ubuntu 24.04/26.04 LTS: `setup-server.sh --rolle dev|prod
  --dns hetzner|cloudflare|acmedns --email …` richtet Docker mit Compose (offizielles apt-Repo),
  Tailscale, Firewall und genau einen Edge-Caddy ein, der HTTP/HTTPS annimmt und an die
  Anwendungen weiterreicht. Zertifikate von Let's Encrypt über ACME DNS-01 — der Server muss
  nicht aus dem Internet erreichbar sein. Dev-Server liegen nur im Tailnet, Prod-Server sind
  öffentlich auf 80/443; SSH nur über Tailscale, ohne sich auszusperren. `--check` belegt den Stand.
- `edge-site add <host> <container>:<port>` schließt eine Anwendung an: auf dem Dev-Server unter
  `dev.<host>`, A-Record über die Hetzner- bzw. Cloudflare-API; für Anbieter ohne API einmalig ein
  CNAME auf acme-dns, danach erneuert Caddy allein. Dazu `list`, `remove` und `check`
  (DNS, Zertifikat, HTTPS).
- **Rollout auf Auftrag:** `rollout <app> jetzt [tag]` spielt ein GitHub-Release auf dem
  Prod-Server ein (Lieferdateien des Tags holen, dann `deploy/update.sh` mit Sicherung und
  Rückweg); `rollout <app> planen "JJJJ-MM-TT HH:MM" [tag]` legt einen einmaligen Termin
  (Europe/Vienna) an, der einen Neustart übersteht und sich nach dem Lauf entfernt. Der Tag wird
  beim Planen festgeschrieben. Dazu `liste`, `absagen`, `status`, `einrichten`, `token`. Ohne
  Auftrag passiert nichts.
- **Skill `/rollout`**: zeigt Lage und Änderungen seit der laufenden Fassung, holt die Freigabe
  und führt den Rollout bzw. Termin per SSH aus. `/deploy-check` verweist darauf.
- **Dev-Instanz auf dem Dev-Server** für laravel, fastapi, astro und wordpress: `deploy/dev.sh up`
  baut aus dem Arbeitsstand, startet mit eigener Datenbank (`compose.dev.yaml`, Container
  `…-dev`) und schließt die Anwendung unter `https://dev.<APP_DOMAIN>` an. Neuer Schlüssel
  `APP_DOMAIN` in `.env.example`; `deploy/install.sh` schließt die Anwendung auf Servern nach dem
  Standard selbst an den Edge-Caddy an.

- **Kochbuch `EINRICHTUNG.md` neu gegliedert:** Teil A Arbeitsplatz, B Dev-Server, C Prod-Server,
  D DNS und Zertifikate (Hetzner, Cloudflare, acme-dns mit einmaligem CNAME), E Rollout.

### Geändert

- **Lieferweg:** entwickelt und getestet wird auf dem Dev-Server, nach Abnahme PR, Merge und
  Release, auf den Prod-Server kommt ein Release nur per `rollout` (Kern, Overlays, Befehlstabellen).
  WordPress läuft nicht mehr im lokalen Verbund unter `localhost:8080`, sondern als Dev-Instanz.
- **Einrichtung des Arbeitsplatzes:** Docker gehört zu keinem Stack mehr — nur noch im Notfall mit
  `--stack docker`. Neu in der Grundausstattung: Tailscale, VS Code mit Remote-SSH und ein
  SSH-Schlüssel, um auf dem Dev-Server zu arbeiten. Auf dem Dev-Server selbst entfallen sie.

## [0.8.1] — 2026-09-22

### Geändert

- Stack-Regeln `fastapi` und `nextjs` ohne PCN-Repos als Beispiele.
- Die Lesekopien nach dem Release (`scripts/nach-release.sh`) liegen jetzt im OneDrive der
  CoreVision Systems GmbH, Ordner „Standards“.

## [0.8.0] — 2026-09-22

### Hinzugefügt

- **Einrichtungs-Kochbuch `EINRICHTUNG.md`** im Verteil-Repo: ein neues Windows-, macOS- oder
  Linux-Gerät vollständig einrichten — per Skript oder von Hand, mit Verzeichnisstruktur
  (`~/Code`, `~/Tresor`), Werkzeugen je Stack samt offizieller Quelle, den Handgriffen
  (Anmeldungen, Git-Identität, Tresor-Datei, Herd, WSL2 und Docker Desktop), Kontrolle,
  Aktualisierung, Fehlerbildern und Rückweg.
- Einrichtungsskripte: `--stack`/`-Stack` installiert die Werkzeuge eines Stacks (PHP 8.4 mit
  `intl`, Composer, Laravel-Installer, Node 24, Docker, Python 3.12, pipx mit ruff und pytest,
  ShellCheck, PSScriptAnalyzer); `--check`/`-Check` prüft ein Gerät, ohne etwas zu
  installieren; `--liste`/`-Liste` zeigt, was ein Stack braucht und woher es kommt. Die
  Grundausstattung enthält jetzt KeePassXC und die Ordner `~/Code` und `~/Tresor`.
- Das Einrichtungsskript schaltet die **automatische Aktualisierung** des Standards ein: Neue
  Fassungen kommen beim Start einer Session von selbst. Offene Handgriffe nennt es am Ende
  einzeln, statt sie stillschweigend zu überspringen.

### Geändert

- GitHub CLI kommt unter Debian/Ubuntu aus dem offiziellen apt-Repo von GitHub.
- `setup.ps1` schließt bei einem Fehler nicht mehr das PowerShell-Fenster (`irm | iex`).

- Der Standard ist allein Sache der CoreVision Systems GmbH. `/projekt-neu` bietet als Firma
  nur noch „CoreVision Systems“ oder einen anderen Eigentümer an; Rechteinhaber in `LICENSE`
  ist ohne `--company` jetzt „CoreVision Systems GmbH“ (auch bei `/projekt-aufnehmen`).
  Kontakt in Plugin, Marketplace und Rechtetext des Verteil-Repos: `info@cvsystems.ai`.

## [0.7.0] — 2026-09-16

### Hinzugefügt

- **Stack `wordpress`** — für redaktionell gepflegte Websites, deren Inhalte der Kunde selbst im
  Browser pflegt (Firmenseite, Landingpages, Blog). Overlay `stacks/wordpress.md`, Register
  `templates/wordpress/`: WordPress 7 im Bedrock-Layout als Composer-Abhängigkeit, MariaDB 11.8
  (bewusste Abweichung von PostgreSQL, nur für diesen Stack), FrankenPHP als `www-data` mit den
  Rollen `app` und `cron`, Block-Theme `site`, Mu-Plugin `firmenstandard` (`/healthz` mit
  Fassung, Härtung), kein Code aus dem Admin (`DISALLOW_FILE_MODS`, Plugins nur per Composer aus
  `repo.wp-packages.org`), deutsche Sprachpakete beim Bau ins Abbild, `deploy/install.sh` mit
  Erstinstallation (Admin-Passwort einmalig über stdin, Deutsch, Zeitzone, Pflichtseiten,
  Suchmaschinen gesperrt), `deploy/backup.sh` mit `mariadb-dump` und Uploads, `deploy/update.sh`
  mit `wp core update-db`; Prüfungen ohne Datenbank (PHPCS mit WordPress-Coding-Standards,
  PHPStan Stufe 6 mit WordPress-Stubs, Strukturprüfung `tests/pruefe-struktur.php`);
  lokaler Verbund über `compose.dev.yaml`. Skill `/wordpress`, Erkennung über `roots/wordpress`
  in `composer.json` oder `wp-config.php` im Wurzelverzeichnis, Fälle in beiden Tests.
- **Skill `/projekt-aufnehmen`** — Gegenstück zu `/projekt-neu` für Repos, die nicht mit dem
  Standard entstanden sind. `scripts/projekt-aufnehmen.sh` macht eine Bestandsaufnahme in vier
  Stufen (Erklärung, Kontext, Lieferweg, Betriebsvertrag — je Stack aus dem Overlay abgeleitet,
  mit der Vorlage als Verweis) und legt mit `--apply` Stufe 0 und 1 an: `.claude/settings.json`,
  `CLAUDE.md` mit den echten Befehlen aus `composer.json`, `package.json` und `Makefile`,
  `CHANGES.md`, `docs/status.md` und eine ADR „Aufnahme in den Firmenstandard“ mit den Lücken
  (`templates/aufnahme/`), PR-Vorlage, CODEOWNERS, CI-Durchsicht, Dependabot, die
  `.claude/rules` des Stacks, `version.txt` aus dem letzten Tag, bei Stacks ohne Markerdatei
  `.coding-standard`. Nur Fehlendes, nie überschreiben, nur bei sauberem Arbeitsbaum; kein
  Umbau des Codes. Test `scripts/test-projekt-aufnehmen.sh`, Lesekopie `projekt-aufnehmen.MD`.
- `standard-context.sh --stacks` gibt nur die erkannten Stacks aus, ohne Aktivierung — die
  Erkennung gibt es damit nur an einer Stelle; das Aufnahme-Skript nutzt sie.
- Einrichtungsskripte für neue Coder im Verteil-Repo: `setup/setup.ps1` (Windows) und
  `setup/setup.sh` (macOS/Linux/WSL) installieren Git, GitHub CLI und Claude Code, fügen den
  Marketplace hinzu, installieren das Plugin und prüfen — Vorhandenes wird übersprungen,
  `-DryRun`/`--dry-run` zeigt nur, `-GitHubLogin`/`--github-login` meldet gh an. README und
  Rechtetext des Verteil-Repos liegen jetzt unter `verteilung/` und werden mit veröffentlicht.

### Geändert

- Stack-Wahl-Regel in `/projekt-neu`, `/coding`, beiden READMEs und den Overlays `laravel`,
  `astro` und `nextjs`: Pflegt der Kunde die Inhalte selbst im Browser, ist es `wordpress`;
  pflegt ein Entwickler sie im Repo, bleibt es `astro`.

## [0.6.0] — 2026-09-14

### Geändert

- **Verteilung über das öffentliche Repository `CoreVision-Systems-GmbH/coding-plugins`.** Der
  Workflow `publish.yml` spiegelt bei jedem Release `plugins/coding-standard` und das Marketplace-
  Manifest dorthin; die Projekt-Vorlage `.claude/settings.json` zeigt auf das Verteil-Repo und hat
  `autoUpdate: true`. Installieren braucht kein GitHub-Konto mehr.
- `/projekt-neu`: Eigentümer-Regel — CoreVision Systems und PCN GmbH landen beide in der
  Organisation; Rückfall ist das aktive Konto, nicht mehr `ghubpcn`.
- Beispiele in Skript, Skill, Test und Vorlagen ohne Kunden- und Kontonamen (Musterkunde,
  musterorg, host1).

### Hinzugefügt

- `/release`: neuer Schritt „Nacharbeit des Repos“ — liegt `scripts/nach-release.sh` im Repo, wird
  es nach dem GitHub-Release aufgerufen. Im Plugin-Repo verteilt es die Lesekopien für Menschen:
  `projekt-neu.MD` und den Spiegel `projekt-neu/` (Skill, Skript, Test, Kern, Overlays, Vorlagen)
  in den OneDrive-Ordner „Standards“; dazu `scripts/test-nach-release.sh`.

## [0.5.0] — 2026-09-13

### Hinzugefügt

- Git-Guard: Markerdatei `.git-guard-main-ok` im Arbeitsverzeichnis der Session erlaubt den
  Push auf `main`/`master` — für Doku- und Backup-Repos ohne PR-Fluss (Notiz-Vault). Force-Push,
  Löschen von Remote-Zweigen, `reset --hard`, `clean -f`, `branch -D` und `rm -rf` bleiben auch
  dort geblockt. Sechs neue Testfälle (44–49).

### Behoben

- Stack `script`: `tests/test_beispiel_sh.sh` der Vorlage hatte drei `A && B || C`-Ketten (shellcheck SC2015). Die CI eines frisch angelegten Projekts war damit beim ersten Lauf rot, obwohl der Test lokal grün war (shellcheck läuft nur in der CI). Jetzt `if/else`. Aufgefallen bei `cvs-cvsx100` am 2026-09-12.

### Entfernt

- `docs/handbuch.md` und `scripts/handbuch-docx.py`: Das Handbuch Augmented Coding wird seit
  2026-09-11 außerhalb des Repositories geführt (KI-OS-Vault, `12-doku/`) und als PDF
  weitergegeben. README verweist dorthin. Keine Regeländerung.

## [0.4.3] — 2026-09-11

### Behoben

- `scripts/apply-rulesets.sh` rief die API mit führendem Schrägstrich (`/repos/…`) auf; Git Bash
  unter Windows wandelt das in einen Windows-Pfad um, und das Skript meldete „Repo nicht
  erreichbar“. Pfade jetzt ohne Schrägstrich; Org-Weg an `cvs-rag` geprobt. Die Vorlagen
  unter `rulesets/org/` haben LF-Zeilenenden.

## [0.4.2] — 2026-09-11

### Geändert

- **Rulesets über die Organisation.** `CoreVision-Systems-GmbH` trägt drei Org-Rulesets
  `main geschuetzt · <check>` (`ci`, `policy-and-tests`, `deterministic-contracts`), die
  über die Custom Property `ci-check` greifen: PR-Pflicht, Pflicht-Check, kein Force-Push,
  kein Löschen, lineare Historie, Squash als einzige Merge-Art. `scripts/apply-rulesets.sh`
  setzt für Org-Repos nur noch die Property (Vorgabe `ci`), für Benutzerkonten weiter das
  Repo-Ruleset aus `rulesets/main.json`. Vorlagen der Org-Rulesets unter `rulesets/org/`.
- Abschlussbericht von `/projekt-neu` nennt den neuen Weg.

## [0.4.1] — 2026-09-11

### Geändert

- Das Repository liegt jetzt in der Organisation `CoreVision-Systems-GmbH`. Marketplace-Quelle
  in der Repo-Vorlage (`templates/repo/.claude/settings.json`), Homepage des Plugins, README und
  Handbuch zeigen auf `CoreVision-Systems-GmbH/claude-standard`. Repos mit der alten Quelle
  `ghubpcn/claude-standard` funktionieren über die Weiterleitung von GitHub weiter und werden
  beim nächsten Anfassen umgestellt.

### Hinzugefügt

- Handbuch für Programmierer `docs/handbuch.md` (Repo-Wurzel) mit Word-Export
  `scripts/handbuch-docx.py`; Handbuch-Fassung = Plugin-Fassung.

## [0.4.0] — 2026-09-11

Die Stack-Leitlinie steht jetzt im Standard: Laravel für alles Datennahe, React über Inertia
nur, wo die Oberfläche es verlangt, Astro für öffentliche Content-Sites — und Next.js als
Ausnahme mit Auflagen statt als Stack.

### Hinzugefügt

- **Stack `astro`** — Overlay `stacks/astro.md`, Register `templates/astro/` (statisches
  Astro 7, gebaut in `node:24-alpine`, ausgeliefert aus `caddy:2-alpine` hinter dem
  Edge-Caddy, `/healthz` mit Fassung, Lieferweg wie bei den anderen Abbildern; keine Daten,
  deshalb keine Sicherung), Skill `/astro`, Erkennung über `astro` in `package.json`, Fälle in
  beiden Tests.
- **Overlay `stacks/nextjs.md`** — die Ausnahme mit drei Bedingungen (indexierbar mit
  Umsatzziel, Anforderung über Inertia SSR und Astro hinaus, Budget für den Zweitbetrieb) und
  den Auflagen für den Betrieb: `standalone` mit `public/` und `.next/static`, eine Instanz,
  Proxy ohne Puffer und ohne `x-middleware-subrequest`, Active LTS mit Sieben-Tage-Patchfenster,
  Laravel bleibt Identitätsquelle. Gilt für den Bestand; `/projekt-neu` bietet Next.js nicht an.
- **Stack-Wahl-Regel** in `/projekt-neu` (die Interview-Frage „Stack“ markiert die Empfehlung)
  und in beiden READMEs.

### Geändert

- **`stacks/laravel.md`**: Fläche „öffentlich“ (Inertia mit SSR je Route oder Blade mit Cache;
  Content-Sites gehören nach `astro`), vier Kriterien für Inertia + React (mindestens zwei
  müssen zutreffen), Filament-Grenzlinie (Backoffice, Verwaltung, Kundenportal als zweites
  Panel; Tenancy scoped nur im Panel), Abschnitt „Fassungen“ (PHP 8.4, Laravel ^13,
  Filament ^5.4, Livewire ^4.1, Inertia 3 mit React 19, Pest 5 statt 4, Wayfinder 0.1 als Beta
  nur für Routen) mit Upgrade-Rhythmus, SSR-Rolle im Betriebsvertrag, neue Fallen zu Laravel 13
  (`PreventRequestForgery`, `cache.serializable_classes`, `upsert()`), Livewire 4 (`.deep`,
  `.live.blur`) und Wayfinder.
- `/coding` kennt die Marker für `astro`, `nextjs` und `.coding-standard`.
- Der Hook-Test erwartet für Next.js jetzt das Overlay statt des Hinweises „kein Overlay“.
- `projekt-neu.sh` weist einen Zweck mit geradem Anführungszeichen oder Backslash ab — er
  landet unverändert in Quelltexten und brach den Bau des Astro-Gerüsts (Review-Befund).
- Der lokale Baubefehl in den Compose-Kommentaren aller drei Abbild-Stacks setzt
  `APP_VERSION=local` voraus; ohne `.env` scheiterte er an der Pflichtvariable.

## [0.3.0] — 2026-09-11

Ein neues Projekt entsteht jetzt in einem Zug: Gerüst, Vorlagen, Repository, Vault-Eintrag.
Was danach noch von Hand zu tun ist, steht im Abschlussbericht — nichts davon versteckt sich.

### Hinzugefügt

- **Skill `/projekt-neu`** — ein gebündeltes Interview (Name, Zweck, Stack, Firma und
  GitHub-Eigentümer, Kunde), Zusammenfassung mit Freigabe, dann der Bootstrap. Bei Laravel
  danach die Firmenstandard-Nacharbeit, die kein Installer kennt: Fassung in
  `config/app.php` und in beiden Oberflächen, `TrustProxies`, `composer.json`-Scripts,
  Larastan Stufe 8, `AppVersionTest`. Die Nacharbeit läuft auf einem Zweig und kommt per PR
  mit grüner CI nach `main` — zugleich der erste Beweis, dass die erzeugte CI auf GitHub
  durchläuft.
- **Bootstrap `scripts/projekt-neu.sh`** — deterministisch, ohne Rückfragen, mit `--help`
  und `--list-stacks`. Prüft Name, Stack, Werkzeuge und Zielordner, baut das Gerüst, setzt
  die Vorlagen mit ersetzten Platzhaltern ein, legt `git init -b main` und einen Commit an,
  erzeugt auf Wunsch das private Repository und schreibt den Vault fort
  (`04-projects/<name>/README.md` plus eine Zeile im heutigen Daily Log). Setzt das
  Ausführbar-Bit der Skripte im Git-Index — unter Windows (`core.fileMode=false`) käme es
  sonst nie ins Repository, und `./deploy/update.sh` scheiterte auf dem Server — und trägt
  in `CODEOWNERS` bei einer Organisation als Eigentümer das aktive gh-Konto ein. Test
  `scripts/test-projekt-neu.sh` (Argumentprüfung, Register, zwei echte Proben mit
  `--no-github`).
- **Stack-Register** — ein Stack ist ab jetzt Overlay **plus** Ordner unter `templates/`
  mit `stack.conf` (`LABEL`, `DESCRIPTION`, `REQUIRES`, `CONTAINERIZED`, `MARKER`),
  `befehle.md`, optional `scaffold.sh` und `dateien/`. `templates/_vorlage/` ist die
  Kopiervorlage.
- **Stack `script`** mit Overlay `stacks/script.md` — natives Coding ohne Framework
  (Bash, PowerShell, Python): Idempotenz, `--help`/`--dry-run`, Fehlerausgang, keine
  Geheimnisse in Argumenten, Portabilität Windows/Linux, Lieferung als Release-Tarball
  statt Abbild. Die Vorlage bringt ein Beispielwerkzeug in Bash und in Python mit, dazu
  je einen Test und eine CI, die nur prüft, was im Repo wirklich vorkommt.
- **Stack-Vorlagen für `laravel` und `fastapi`** — verallgemeinert aus dem Piloten
  `elitec-leadmgmt`: `Dockerfile`, `compose.yaml`, `compose.build.yaml`,
  `deploy/{install,update,backup}.sh`, `.env.example` mit Kommentar je Schlüssel,
  `tests.yml` und `release.yml` (Actions auf Commit-SHA gepinnt, kein `latest`, Digest in
  den Release-Notizen), `.claude/rules/` je Fläche. FastAPI bringt zusätzlich ein
  lauffähiges Gerüst mit `app/main.py`, `app/settings.py`, einem Beispielmodul, Tests und
  gepinnten Abhängigkeiten; sein `scaffold.sh` lässt `ruff`, `mypy --strict` und `pytest`
  einmal durchlaufen, bevor das Projekt ausgeliefert wird.
- **Gemeinsame Projektvorlagen erweitert** (`templates/repo/`): `CLAUDE.md` und `README.md`
  als Gerüst, `CHANGES.md`, `version.txt`, `LICENSE`, `.editorconfig`, `.gitattributes`,
  `.github/workflows/claude-review.yml` (per Variable `CLAUDE_REVIEW_ENABLED`
  scharfgeschaltet) und ADR `0001-projektstart.md`.
- **Markerdatei nennt den Stack** — `standard-context.sh` liest aus `.coding-standard`
  Zeilen `stack: <name>` und lädt die genannten Overlays zusätzlich. Damit bekommen Stacks
  ohne eigene Markerdatei (wie `script`) ihr Overlay. Doppelte werden zusammengefasst.

### Geändert

- **Echte Umlaute überall** — Vorlagen, Bootstrap, Gerüst-Skripte und Testausgaben
  schreiben deutsche Texte mit ä, ö, ü und ß statt ae/oe/ue/ss. Bezeichner, Schlüssel,
  Pfade und Befehle bleiben ASCII.
- **Die Projektvorlagen sind ins Plugin gewandert** (`templates/repo/` →
  `plugins/coding-standard/templates/repo/`). Der Marketplace installiert nur das
  Plugin-Verzeichnis; vom Repo-Wurzelverzeichnis aus wären die Vorlagen zur Laufzeit nicht
  erreichbar gewesen. `.github/dependabot.yml` liegt jetzt je Stack passend in
  `templates/<stack>/dateien/`, `.github/CODEOWNERS` trägt den Platzhalter
  `* @{{OWNER_USER}}`.

### Behoben

- **`test-standard-context.sh` war rot** — die drei Einzelstack-Fälle prüften noch auf ein
  Zeilenende nach dem Stacknamen, seit 0.2.1 steht dort aber eine schließende Klammer.

## [0.2.1] — 2026-09-11

### Behoben

- **Der Standard kam nur zu einem Sechstel an.** Claude Code blendet Hook-Ausgaben über
  rund 2 KB nur als Vorschau ein und lagert den Rest in eine Datei aus — Kern plus Overlay
  sind 10–15 KB. Der SessionStart-Hook gibt deshalb keinen Volltext mehr aus, sondern eine
  kurze Anweisung, `core/kern.md` und die erkannten Overlays mit dem Read-Tool zu lesen,
  samt den harten Regeln als Kurzform (unter 1,8 KB, im Test abgesichert). Gleiches Verhalten
  bei JSON-`additionalContext` gemessen.

## [0.2.0] — 2026-09-11

Der Standard gilt jetzt von selbst — wer ein erklärtes Repo öffnet, arbeitet danach, ohne
etwas aufzurufen. Kern und Stack-Overlays sind getrennte Dateien; ein Stack ist eine
ausgefüllte Vorlage.

### Hinzugefügt

- **Kern** `core/kern.md` — die stack-unabhängigen Regeln in ≈ 50 Zeilen; übernimmt die
  vier Karpathy-Grundsätze (Annahmen nennen, kleinste Lösung, chirurgische Änderungen,
  prüfbare Ziele) einmal und ersetzt damit die separate Karpathy-`CLAUDE.md`.
- **Stack-Overlays** `stacks/laravel.md` (Kürzung des bisherigen `/laravel` auf
  Entscheidungen, Werkzeugkette, Betriebsvertrag, Fallen) und neu `stacks/fastapi.md`
  (Python 3.12, `app/`-Aufbau, `settings.py` als eine Konfigurationsstelle, `/healthz`,
  Uvicorn hinter dem Edge-Caddy, ruff/pytest/pip-audit); `stacks/_vorlage.md` für neue Stacks.
- **Hook `standard-context.sh`** (`SessionStart`: startup, resume, clear, compact) — gibt
  Kern und erkannte Overlays als Kontext aus, wenn das Repo den Standard erklärt
  (`coding-standard@corevision` in `.claude/settings.json` oder Markerdatei
  `.coding-standard`). Erkennung: `composer.json` mit `laravel/framework`,
  `requirements*.txt`/`pyproject.toml` mit `fastapi`, `package.json` mit `next`.
  Notausgang `CODING_STANDARD_OFF=1`. Test `test-standard-context.sh` (10 Fälle).
- **Skill `/fastapi`** als manueller Schalter für das FastAPI-Overlay.

### Geändert

- **`/coding`** ist kein Regeltext mehr, sondern ein Schalter: lädt Kern und Overlay von
  Hand und fährt die Startroutine — für Cowork-Sessions oder Repos ohne Erklärung.
- **`/laravel`** ebenso: lädt `stacks/laravel.md`, stellt Fassungen fest, UI-Flächen-Entscheid.
- **Lockerungen gegenüber 0.1.0:** Plan Mode mit Freigabe nur noch bei Datenmodell,
  Berechtigungen, Lieferweg oder Änderungen, die sich nicht in einem Satz beschreiben
  lassen; Abschlussbericht nur bei einem PR; Review in frischem Kontext nur bei PRs mit
  Code; Bugfix-Test-zuerst mit begründeter Ausnahme. Definition of Done: Kundeninstanzen
  werden nach Freigabe über den Standardweg ausgerollt, nicht „sofort“.

## [0.1.0] — 2026-09-10

Erste Fassung des Firmenstandards als Plugin.

### Hinzugefügt

- **Skill `/coding`** — Arbeitsstandard als Session-Overlay: Verstehen vor dem Coden,
  Plan mit Prüfungen und Abschnitt „Nicht Teil davon", kleine überprüfbare Schritte,
  Beweis statt Behauptung beim Verifizieren, Testregeln, Git- und GitHub-Regeln,
  Dokumentationspflichten, Sicherheit und Betrieb, Umgang mit Subagenten und Kontext,
  Definition of Done und Abschlussbericht.
- **Skill `/laravel`** — Stack-Overlay für Laravel 13, Filament 5 und Inertia/React:
  Zuständigkeiten, UI-Flächen-Entscheid, gemeinsame Anwendungsarchitektur,
  nicht verhandelbare Grenzen, Verifikationsliste, Abschlussbericht. Dazu der
  **Betriebsvertrag** mit zehn Regeln zu Runtime (FrankenPHP klassisch, drei Rollen aus
  einem Image), ENV, CI, generierten Artefakten, Filament-Middleware-Stapel, Caches zur
  Laufzeit, Qualitäts-Gates, Version im Produkt, Windows-Toolchain und Laravel Boost.
- **Skill `/release`** — Voraussetzungen prüfen, Version nach SemVer aus den Commits
  vorschlagen und bestätigen lassen, `CHANGES.md` abschließen, Release-PR durch die CI,
  Tag und GitHub-Release anlegen, Image-Referenz mit Digest berichten.
- **Skill `/deploy-check`** — Prüfliste vor dem Update einer Kundeninstanz: Ziel-Tag und
  Digest, Migrationen additiv, ENV-Schlüssel, Drift auf dem Server, Sicherung und
  Plattenplatz, Gesundheit und laufende Version. Ausgabe als Go/No-Go-Tabelle. Führt
  kein Update aus.
- **Skill `/pr`** — Draft-PR aus dem aktuellen Branch: Titel als Conventional Commit,
  Body nach der PR-Vorlage des Repos, CI-Status abrufen. Kein Merge.
- **Hook `git-guard`** — `PreToolUse` auf dem Bash-Tool. Blockiert Force-Push, Push direkt
  auf `main`/`master`, Löschen von Remote-Zweigen, `git reset --hard`, `git clean -f`,
  `git branch -D`, `git checkout -- .`, `git restore .` und `rm -rf` auf gefährliche Ziele.
  Tags pushen bleibt erlaubt. Ohne `jq`, damit er unter Windows läuft.
- **Test `test-git-guard.sh`** — 43 Fälle, blockiert und erlaubt.
- **Agents** — `reviewer`, `security-reviewer`, `laravel-reviewer`, `database-reviewer`,
  `python-reviewer`, `typescript-reviewer`, `build-fixer`. Gemeinsames Ausgabeformat mit
  Belegpflicht und Abschnitt „Nicht geprüft".
- **Repo-Vorlagen** unter `templates/repo/` — `.claude/settings.json` zum Anschließen des
  Marketplace, PR-Vorlage, `CODEOWNERS`, `dependabot.yml`, `docs/status.md` und die
  ADR-Vorlage.
- **Ruleset** `rulesets/main.json` und `scripts/apply-rulesets.sh` — PR-Pflicht,
  Status-Check `ci`, kein Force-Push, kein Löschen, lineare Historie, Squash als
  einzige Merge-Art.
