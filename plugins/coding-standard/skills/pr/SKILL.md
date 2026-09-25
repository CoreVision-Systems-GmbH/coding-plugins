---
name: pr
description: Legt aus dem aktuellen Branch einen Draft-PR an — Titel als Conventional Commit, Body nach der PR-Vorlage des Repos, danach einmal den CI-Status abrufen. Merged nicht. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: [Hinweis für Titel oder Body]
---

# Draft-PR anlegen

Zusatzhinweis aus dem Aufruf: `$ARGUMENTS`

Dieser Skill legt einen **Draft**-PR an. Er merged nicht, setzt nicht auf „Ready for review"
und ändert keinen Anwendungs-Code.

## 1. Voraussetzungen

1. Aktuellen Branch lesen: `git rev-parse --abbrev-ref HEAD`.
   Ist er `main` oder `master`: **abbrechen** und sagen, dass die Arbeit auf einen eigenen
   Branch gehört (`feat/…`, `fix/…`, `chore/…`, `docs/…`).
2. Arbeitsbaum prüfen (`git status --porcelain`). Uncommittete Änderungen nennen und fragen,
   ob sie noch in den PR sollen — nicht stillschweigend committen.
3. Ist der Branch noch nicht gepusht (`git rev-parse --abbrev-ref @{u}` schlägt fehl):
   `git push -u origin <branch>`.
4. Gibt es für den Branch schon einen PR (`gh pr view --json number,url,isDraft`):
   nicht doppelt anlegen — die URL nennen und stattdessen fragen, ob der Body aktualisiert
   werden soll.

## 2. Titel ableiten

Aus den Commits des Branches (`git log origin/main..HEAD --pretty=%s`) einen Titel bilden:

```text
<typ>: <Beschreibung auf Deutsch>
```

- Typ englisch und aus dem festen Satz: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`,
  `perf`, `ci`.
- Beschreibung deutsch mit echten Umlauten, Kleinschreibung nach dem Doppelpunkt,
  kein Punkt am Ende.
- Gibt es genau einen Commit, ist dessen Betreff meist schon der Titel.
- Gibt es mehrere, den gemeinsamen Nenner benennen — nicht die Commits aufzählen.
- Bringt der Branch einen Bruch (`!` oder `BREAKING CHANGE`), das `!` im Titel behalten.

## 3. Body füllen

Vorlage in dieser Reihenfolge suchen:

1. `.github/pull_request_template.md` im Repo
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. sonst die Vorlage dieses Plugins:
   `${CLAUDE_PLUGIN_ROOT}/templates/pull_request_template.md`
   (Claude Code kopiert nur den Plugin-Ordner in seinen Cache — Pfade außerhalb davon
   lösen nicht auf.)

Die Abschnitte füllen — mit dem, was wirklich passiert ist:

- **Was / Warum** — aus den Commit-Bodies und dem Diff (`git diff origin/main...HEAD --stat`
  für den Umfang, dann die tatsächlich geänderten Stellen ansehen). Das *Warum* steht nicht
  im Diff; es kommt aus den Commit-Bodies, dem Issue oder `$ARGUMENTS`. Fehlt es, sag das
  im PR offen, statt eines zu erfinden.
- **Abnahmekriterien** — A1…An aus dem Auftrag (Plan, Issue, `$ARGUMENTS`), je mit Nachweis
  (Testfall, Datei:Zeile, Klickweg) und der Invariante, die erhalten bleibt. Fehlen sie im
  Auftrag, aus dem Diff ableiten und als Vorschlag kennzeichnen.
- **Prüfweg** — nur Befehle, die in dieser Session tatsächlich gelaufen sind, mit Ergebnis.
  Getrennt nach automatisiert (Befehl) und manuell (Klickweg). Nichts eintragen, was nur
  hätte laufen können.
- **Risiko** — was kaputtgehen kann und wer es merkt.
- **Migration / ENV-Änderung** — geänderte Dateien unter `database/migrations`, `.env.example`
  oder gleichwertig; ob ein Handgriff beim Update nötig ist. Gibt es nichts: „keine".
- **Prüfprotokoll** — nur bei Rechten, Schema, Mandanten, Anmeldung, Geld oder
  Kundenauslieferung: Soll/Ist je Anforderung mit Beleg, Befunde mit Schwere und Frist,
  bewusst nicht Getanes, Gegenprüfung (zweites Modell oder Mensch), Urteil FREIGEGEBEN /
  BEDINGT / GESPERRT. Wer prüft, hat nicht gebaut. Sonst den Abschnitt aus dem Body löschen.
- **DoD-Checkliste** — nur ankreuzen, was belegt ist.

## 4. Anlegen

Vorher den Body prüfen — dieselbe Prüfung läuft in der CI (Schritt „PR-Text prüfen“):

```bash
bash scripts/pr-text-pruefen.sh <datei>
```

Fehlt der Prüfer im Repo (Bestand vor `/projekt-aufnehmen --apply`), die Kopie des Plugins
nehmen: `bash "${CLAUDE_PLUGIN_ROOT}/templates/repo/scripts/pr-text-pruefen.sh" <datei>`.
Rot heißt: Lücken füllen, nicht anlegen. Dann:

```bash
gh pr create --draft --title "<titel>" --body-file <datei>
```

Den Body über eine Datei übergeben, nicht inline — sonst gehen Umlaute und Zeilenumbrüche
unter Windows verloren.

## 5. Status und Bericht

1. Einmal `gh pr checks` abrufen (ohne `--watch`).
2. Berichten:

```text
PR:        <URL> (Draft)
Titel:     <titel>
Commits:   <n>
CI:        <Status je Check, oder „läuft noch">
Offen:     <was vor „Ready for review" noch fehlt>
```

Kein Merge, kein `--fill`, kein Umstellen auf „Ready for review" — das entscheidet der Nutzer.
