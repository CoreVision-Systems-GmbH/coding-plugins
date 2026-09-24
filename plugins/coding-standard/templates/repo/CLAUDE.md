# {{NAME}} — Hinweise für Claude Code

## Was das ist

{{PURPOSE}}

Stack: {{STACK_LABEL}}. Datenbank: {{DATABASE}}. Eigentümer des Repos: `{{OWNER}}`. Kunde/Instanz: {{CUSTOMER}}.

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
  Bezeichner Englisch und ASCII; Datei- und Branch-Namen ASCII. Deutsche Fachbegriffe in
  Bezeichnern nur, wenn sie im Glossar stehen.
- Kommentare erklären das **Warum**, nicht das Was. Vorfälle werden datiert festgehalten,
  bewusste Nicht-Entscheidungen begründet.
- Zeitangaben immer mit Zeitzone. Die Anwendung läuft in genau einer (`Europe/Vienna`).

## Glossar

<!-- Fachbegriffe, für die es keine gute englische Entsprechung gibt. Je Begriff eine Zeile:
     ASCII-Schreibweise für Code und Datenbank, Schreibweise mit Umlaut für die Oberfläche,
     Bedeutung in einem Satz. Was hier nicht steht, heißt im Code Englisch. Beispiel:
     | `stornogrund` | Stornogrund | Grund, aus dem ein Beleg storniert wurde; Pflichtfeld beim Storno | -->

| Code und Datenbank | Oberfläche | Bedeutung |
| ------------------ | ---------- | --------- |
|                    |            |           |

## Bestätigte Schnittstellen

<!-- Schnittstellen, Spaltennamen und Befehle, die gegen das echte System geprüft wurden —
     damit niemand sie rät (Fehlermuster E). Je Eintrag: was, wo geprüft, wann. Beispiel:
     - `GET /api/kunden/{id}` liefert `{ id, name, kundennummer }` — geprüft gegen Staging am 2026-09-25 -->

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
- Jeder Auftrag hat nummerierte Abnahmekriterien (A1…An); der PR führt sie in der Tabelle
  „Abnahmekriterien“ mit Nachweis, die Abschlusszeile „Geändert“ nennt sie. Befunde, die
  nicht sperren, stehen in `docs/status.md` unter „Rückstände“ mit Termin.
