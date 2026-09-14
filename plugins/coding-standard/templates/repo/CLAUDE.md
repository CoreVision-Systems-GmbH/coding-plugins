# {{NAME}} — Hinweise für Claude Code

## Was das ist

{{PURPOSE}}

Stack: {{STACK_LABEL}}. Eigentümer des Repos: `{{OWNER}}`. Kunde/Instanz: {{CUSTOMER}}.

Der Firmenstandard (`coding-standard@corevision`) ist in `.claude/settings.json` erklärt und
wird bei jedem Session-Start automatisch geladen — Kern plus Stack-Overlay. Was hier steht,
gilt **zusätzlich** und geht dem Overlay vor.

## Befehle

{{COMMANDS}}

## Karte

<!-- Verzeichnis → Zweck. Beim ersten echten Feature ausfüllen und danach fortschreiben;
     eine Karte, die nicht stimmt, ist schlimmer als keine. -->

| Verzeichnis        | Zweck                                              |
| ------------------ | -------------------------------------------------- |
| `docs/decisions/`  | ADR: Kontext, Entscheidung, Folgen                 |
| `docs/status.md`   | Aktueller Stand und nächste Schritte               |

## Konventionen

- Alle Texte Deutsch mit echten Umlauten — Oberfläche, Kommentare, Commits, Doku.
  Bezeichner, Datei- und Branch-Namen bleiben ASCII.
- Kommentare erklären das **Warum**, nicht das Was.
- Zeitangaben immer mit Zeitzone. Die Anwendung läuft in genau einer (`Europe/Vienna`).

## Fallen

<!-- Noch keine. Hier landet nur, was ein Linter nicht findet und die Dokumentation des
     Frameworks nicht hergibt: die Stolperstelle, die schon einmal eine Stunde gekostet hat.
     Ein Eintrag nennt die Falle, das Symptom und die Abhilfe — nicht mehr.
     Stack-typische Fallen stehen im Overlay und gehören nicht hierher. -->

## Regeln

- Branch `feat/…`, `fix/…`, `chore/…`, `docs/…` (kebab-case, ASCII). Nie auf `main` arbeiten.
- Früh einen Draft-PR öffnen und `.github/pull_request_template.md` füllen. Auf `main` kommt
  nur ein PR mit grüner CI, per **Squash-Merge**.
- Commits nach Conventional Commits: Typ englisch, Beschreibung deutsch, ein Anliegen je Commit.
- Jede nutzerrelevante Änderung nach `CHANGES.md` unter **„Unveröffentlicht"** — aus Nutzersicht,
  nicht als Änderungsprotokoll des Codes.
- Release über einen Tag `vX.Y.Z` (`/release`). Stand und nächste Schritte in `docs/status.md`
  fortschreiben, Richtungsentscheidungen als ADR in `docs/decisions/`.
- Beweis statt Behauptung: Prüfbefehle laufen lassen und die Ausgabe zitieren; was nicht
  geprüft wurde, ausdrücklich benennen.
