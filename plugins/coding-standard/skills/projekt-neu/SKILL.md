---
name: projekt-neu
description: Neues Projekt vollständig nach Firmenstandard anlegen — Stack auswählen, Gerüst bauen, Vorlagen einsetzen, GitHub-Repo und Vault-Eintrag, Stack-Nacharbeit und Abschlussbericht mit den offenen Handgriffen. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: [name]
---

# /projekt-neu — neues Projekt nach Firmenstandard

Name aus dem Aufruf (falls angegeben): `$ARGUMENTS`

Das Skript `${CLAUDE_PLUGIN_ROOT}/scripts/projekt-neu.sh` macht die Arbeit. Deine Aufgabe:
die fehlenden Angaben in **einem** Durchgang erfragen, das Skript aufrufen, die Nacharbeit
erledigen, die das Skript nicht kann, und die offenen Handgriffe berichten.

Erfinde nichts. Was du nicht weißt, fragst du — einmal, gebündelt.

## 1. Voraussetzungen feststellen

```bash
gh auth status
bash ${CLAUDE_PLUGIN_ROOT}/scripts/projekt-neu.sh --list-stacks
```

Merke dir das **aktive** gh-Konto und die Liste der Stacks samt Beschreibung. Ist `gh` nicht
angemeldet, sag es und biete `--no-github` an.

## 2. Ein gebündeltes Interview

`AskUserQuestion` nimmt höchstens **vier** Fragen je Aufruf. Deshalb:

- **Name im Aufruf vorhanden** → ein einziger Aufruf mit den vier Fragen unten.
- **Kein Name** → zuerst in einer normalen Nachricht Name und Zweck erfragen (Name kebab-case
  und ASCII, Zweck in zwei Sätzen), danach ein Aufruf mit Stack, Firma/Eigentümer, Kunde.

| Frage | Optionen |
|---|---|
| **Zweck** | Zwei Vorschläge aus Name und Kontext als Optionen; den eigenen Text tippt der Nutzer über „Other". Zwei Sätze: was es tut, für wen. Geht in `CLAUDE.md`, `README.md`, ADR und die Repo-Beschreibung. |
| **Stack** | Die Namen aus `--list-stacks`, jeweils mit LABEL als Beschreibung. Vorher die Stack-Wahl-Regel unten anwenden und den passenden Stack als erste Option mit „(empfohlen)“ markieren. |
| **Firma / GitHub-Eigentümer** | „CoreVision Systems", „PCN GmbH", „anderer (frei eingeben)". |
| **Kunde/Instanz** | „intern" oder frei, z. B. „Musterkunde auf host1". |

Zur Stack-Wahl (aus Name, Zweck und Kontext):

- **datennah** — Datenmodell, Rechte, Verwaltung, Nutzerkonten, Formulare mit Serverlogik →
  `laravel`. Das ist das Arbeitspferd; im Zweifel dieser.
- **Dienst mit JSON-Schnittstelle ohne eigene Oberfläche** → `fastapi`.
- **Werkzeug ohne Laufzeit** — Wartungslauf, Auswertung, Server-Handgriff → `script`.
- **öffentliche Content-Site** — Firmenseite, Landingpages, Doku, Blog; keine Anmeldung → `astro`,
  solange ein Entwickler die Inhalte im Repo pflegt.
- **redaktionell gepflegte Website** — Firmenseite, Landingpages, Blog, deren Inhalte der Kunde
  selbst im Browser pflegt → `wordpress`. Braucht es Anmeldung für Endnutzer, Shop oder Portal,
  ist es `laravel`.
- **Next.js wird nicht angeboten.** Verlangt der Nutzer es, nenne die drei Bedingungen aus
  `${CLAUDE_PLUGIN_ROOT}/stacks/nextjs.md` und die Alternative (`astro` oder `laravel` mit
  Inertia SSR). Der Entscheid liegt beim Nutzer; ein Ja bedeutet Anlage von Hand außerhalb von
  `/projekt-neu`.

Zum Eigentümer:

- **CoreVision Systems** und **PCN GmbH** → Organisation `CoreVision-Systems-GmbH`; dort
  liegen die Repos beider Firmen. Vorher prüfen, dass
  `gh api orgs/CoreVision-Systems-GmbH/memberships/<aktives konto>` eine aktive
  Mitgliedschaft meldet. Sonst sagen, dass die Organisation mit diesem Konto nicht
  erreichbar ist, und das aktive Konto als Eigentümer nehmen.
- **anderer** → der eingegebene Wert, unverändert.

Die Firma bestimmt außerdem `--company` (Rechteinhaber in `LICENSE`); ohne Angabe bleibt es
bei `CoreVision Systems / PCN GmbH`.

## 3. Zusammenfassung und Freigabe

Zeige in sechs Zeilen: Name · Stack · Eigentümer · Zielordner (`~/Code/<name>`) · Kunde ·
ob ein GitHub-Repo entsteht. Warte die Bestätigung ab. Erst danach schreibt irgendetwas.

## 4. Skript ausführen

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/projekt-neu.sh \
  --name <name> --stack <stack> --owner <owner> \
  --purpose "<zweck>" [--customer "<kunde>"] [--company "<firma>"] \
  [--vault <pfad>]
```

`--vault` nur mitgeben, wenn der Vault auf diesem Rechner liegt. Bricht das Skript ab, gib
die Fehlermeldung wörtlich weiter und behebe die Ursache — starte den Lauf nicht blind neu,
der Zielordner ist dann nicht mehr leer.

Zitiere die Ausgabe des Skripts (Kurzfassung: erkannte Werte, Commit, Repo-URL).

## 5. Stack-Nacharbeit — nur Laravel

Der Laravel-Installer kennt den Firmenstandard nicht. Diese Punkte macht **Claude** danach
von Hand, jeder mit einer Prüfung. Vorher `${CLAUDE_PLUGIN_ROOT}/stacks/laravel.md` lesen.
Die Session läuft nicht im neuen Ordner — jeden Befehl mit `cd <zielordner> && …` ausführen
und die Nacharbeit gleich auf einem Zweig beginnen:

```bash
cd <zielordner> && git checkout -b chore/firmenstandard-nacharbeit
```

- [ ] `config/app.php`: `'version' => env('APP_IMAGE_VERSION', 'dev')` ergänzen,
      `'timezone' => env('APP_TIMEZONE', 'UTC')` (nicht hart `UTC`).
- [ ] `bootstrap/app.php`: `$middleware->trustProxies(at: '*');` — sonst erzeugt Laravel
      hinter dem Edge-Caddy `http://`-Adressen.
- [ ] `app/Http/Middleware/HandleInertiaRequests.php`: geteilte Prop
      `'appVersion' => (string) config('app.version')`.
- [ ] Fußkomponente `resources/js/components/app-version.tsx`, eingebunden im Layout der
      Arbeitsoberfläche.
- [ ] `app/Providers/Filament/AdminPanelProvider.php`: Render-Hook
      `PanelsRenderHook::FOOTER` mit derselben Fassung; app-weite Sicherheits-Middleware
      zusätzlich in `authMiddleware([...], isPersistent: true)`.
- [ ] `app/Models/User.php`: `implements FilamentUser` mit `canAccessPanel(Panel $panel)`.
      **Ohne das antwortet `/admin` außerhalb von `local` mit 403.** Gleich die engste
      Bedingung setzen, die das Projekt hergibt (Rolle, Flag) — nicht `true` stehen lassen.
- [ ] `.env.example` ist bereits gesetzt (`APP_VERSION`, `APP_TIMEZONE=Europe/Vienna`) —
      gegenprüfen, dass `laravel new` sie nicht überschrieben hat.
- [ ] `composer.json`-Scripts: `ci:setup` (ohne `migrate`) neben `setup`, dazu `ci:check`,
      `lint`, `lint:check`, `types:check`, `test`. Das Starter-Kit bringt alles außer
      `ci:setup` mit. `types:check` braucht `phpstan analyse --memory-limit=1G` — mit den
      voreingestellten 128 MB stürzt Larastan auf Stufe 8 ab.
- [ ] `phpstan.neon`: `level: 8`, `paths` auf `app/ bootstrap/app.php config/ database/
      routes/`, unter Windows zusätzlich `configDirectories: [config]`. Stufe 8 meldet die
      Settings-Controller des Starter-Kits (`$request->user()` ist `User|null`): den Nutzer
      einmal in eine Variable holen und mit `if (! $user instanceof User) { abort(403); }`
      einengen — keine `@phpstan-ignore`-Kommentare, keine Baseline.
- [ ] `vite.config.ts`: Laravel Boost legt `.pi/`, `.agents/`, `.codex/`, `.cursor/`,
      `AGENTS.md`, `boost.json` und `.mcp.json` an. Diese und die Doku (`docs/**`,
      `CLAUDE.md`, `CHANGES.md`, `README.md`) in **beide** Ausnahmelisten —
      `lint.ignorePatterns` **und** `fmt.ignorePatterns`. Sonst prüft `npm run check`
      51 Dateien, die niemand von Hand geschrieben hat.
- [ ] `tests/Feature/AppVersionTest.php`: die Fassung ist auf **beiden** Oberflächen sichtbar.
- [ ] Windows: Filament und Boost schreiben einzelne Dateien mit CRLF. Einmal
      `composer lint` laufen lassen, sonst scheitert Pint an `bootstrap/providers.php`.

Danach beides laufen lassen und die letzten Zeilen wörtlich zitieren:

```bash
composer test
npm run check && npm run types:check && npm run build
```

Erst wenn beides grün ist — und nur über einen PR, nie direkt auf `main` (den Push dorthin
blockt der Git-Guard ohnehin):

```bash
git add -A && git commit -m "chore: Firmenstandard-Nacharbeit (Fassung, TrustProxies, Prüfungen)"
git push -u origin chore/firmenstandard-nacharbeit
gh pr create --fill
gh pr checks --watch
gh pr merge --squash --delete-branch
```

Der PR ist zugleich der erste Beweis, dass `tests.yml` auf GitHub durchläuft — bleibt er rot,
ist das der nächste Arbeitsschritt, nicht der Merge. Der allererste CI-Lauf auf `main` (vom
Push des Gerüsts) ist bei Laravel erwartbar rot: `composer ci:setup` entsteht erst mit dieser
Nacharbeit. Ohne Repository (`--no-github`) gibt es keinen Remote: dann direkt auf `main`
committen.

Für **astro**, **fastapi**, **script** und **wordpress** gibt es keine Nacharbeit — deren
Gerüst kommt vollständig aus den Vorlagen und ist im Lauf des Skripts bereits geprüft worden.
Bei `astro` bleibt ein Handgriff aus dem Abschlussbericht: `site` in `astro.config.mjs` auf die
echte Domain setzen. Bei `wordpress` bleiben zwei: `WP_HOME` in der `.env` der Instanz auf die
echte Domain, und Impressum sowie Datenschutzerklärung befüllen — `deploy/install.sh` legt beide
Seiten leer an.

## 6. Abschluss

Gib die Liste **Offene Handgriffe** aus dem Abschlussbericht des Skripts wieder — sie ist die
eigentliche Übergabe. Schließe mit:

> Claude jetzt in `<zielordner>` neu starten — ab dann gilt der Standard automatisch.
