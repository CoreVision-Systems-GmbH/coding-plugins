---
name: release
description: Führt ein Release durch — Version nach SemVer aus den Commits vorschlagen, CHANGES.md abschließen, Release-PR über die CI bringen, Tag und GitHub-Release anlegen und die Image-Referenz berichten. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: [major|minor|patch|X.Y.Z]
---

# Release

Gewünschter Sprung oder feste Version aus dem Aufruf: `$ARGUMENTS`
(leer = du schlägst die Version vor)

Dieser Skill ändert **keinen** Anwendungs-Code. Er ändert nur `CHANGES.md` und `version.txt`,
legt einen Release-Branch, einen PR, einen Tag und ein GitHub-Release an.

Harte Regeln, die über allem stehen:

- Nie direkt auf `main` pushen — auch nicht den Release-Commit.
- Ist ein CI-Lauf rot, wird gestoppt und berichtet. Kein Weiterdrücken, kein Neustarten
  des Laufs in der Hoffnung, dass es beim zweiten Mal grün wird.
- Kein Force-Push, kein `--admin`-Merge, kein Umgehen der Branch-Regeln.

## 1. Voraussetzungen prüfen

Alle Punkte prüfen und das Ergebnis nennen. Ist einer nicht erfüllt: **abbrechen** und
genau sagen, welcher und warum.

1. Aktueller Branch ist `main` (`git rev-parse --abbrev-ref HEAD`).
2. Arbeitsbaum ist sauber (`git status --porcelain` gibt nichts aus).
3. `git fetch --tags origin`, danach ist lokal identisch mit `origin/main`
   (`git rev-parse HEAD` == `git rev-parse origin/main`).
4. Der letzte CI-Lauf auf `main` ist grün:
   `gh run list --branch main --limit 1`.
5. `CHANGES.md` hat unter `## Unveröffentlicht` mindestens einen Eintrag.
   Ist der Abschnitt leer, gibt es nichts zu veröffentlichen.

## 2. Version bestimmen

1. Letzten Tag lesen: `git describe --tags --abbrev=0 --match 'v*'`.
   Gibt es keinen Tag, schlage `1.0.0` vor.
2. Commits seither lesen: `git log <tag>..HEAD --pretty=%s`.
3. Nach Conventional-Commit-Typ auswerten:

   | Befund | Sprung |
   |---|---|
   | `!` nach dem Typ (`feat!:`, `fix!:`) oder `BREAKING CHANGE` im Body | MAJOR |
   | Eine Migration oder ENV-Änderung, die einen Menschen braucht (Handgriff beim Update) | MAJOR |
   | Mindestens ein `feat` | MINOR |
   | sonst (`fix`, `perf`, `refactor`, `docs`, `chore`, `ci`, `test`) | PATCH |

4. Ein Argument (`major`, `minor`, `patch` oder eine feste `X.Y.Z`) überschreibt den Vorschlag.
5. Den Vorschlag mit Begründung nennen — welcher Commit den Ausschlag gibt — und
   **auf Bestätigung des Nutzers warten**. Ohne Bestätigung geht es nicht weiter.

## 3. Release-PR

1. `git checkout -b release/vX.Y.Z`
2. `CHANGES.md` bearbeiten:
   - `## Unveröffentlicht` umbenennen in `## [X.Y.Z] — YYYY-MM-DD` (heutiges Datum).
   - Darüber eine neue, leere `## Unveröffentlicht` setzen.
3. `version.txt` mit `X.Y.Z` schreiben.
4. `git add CHANGES.md version.txt && git commit -m "chore(release): vX.Y.Z"`
5. `git push -u origin release/vX.Y.Z`
6. `gh pr create --title "chore(release): vX.Y.Z" --body "<Zusammenfassung der Änderungen aus CHANGES.md>"`
7. `gh pr checks --watch`
8. Bei grün: `gh pr merge --squash --delete-branch`
9. `git checkout main && git pull`

Wird die CI rot: stoppen, den fehlgeschlagenen Job nennen, den Release-Branch stehen lassen
und dem Nutzer berichten. Nichts reparieren — das ist Arbeit für eine eigene Session.

## 4. Release anlegen

1. Den Abschnitt `## [X.Y.Z]` aus `CHANGES.md` in eine Notizdatei extrahieren
   (bis zur nächsten `## `-Überschrift, ohne diese).
2. `gh release create vX.Y.Z --target main --title "vX.Y.Z" --notes-file <datei>`

Das erzeugt den Tag und löst `release.yml` aus.

## 4a. Nacharbeit des Repos

Liegt im Repo eine Datei `scripts/nach-release.sh`, jetzt ausführen:

```bash
bash scripts/nach-release.sh vX.Y.Z
```

Sie erledigt, was dieses Repo nach einem Release zusätzlich braucht — im Plugin-Repo zum
Beispiel die Lesekopien für Menschen (Ordner „Standards“ auf OneDrive). Die Ausgabe wörtlich
in den Bericht übernehmen. Gibt es die Datei nicht, entfällt der Schritt. Ein Fehler hier
macht das Release nicht ungültig — Tag und GitHub-Release stehen bereits —, gehört aber in
den Bericht.

## 5. Release-Workflow beobachten

1. `gh run watch` für den Release-Workflow.
2. Danach die Image-Tags und den Digest aus den Release-Notizen bzw. der Workflow-Ausgabe
   lesen. Der Digest (`sha256:…`) ist die eigentliche Referenz — der Tag kann wandern.

## 6. Bericht

```text
Version:        X.Y.Z (Sprung: … , weil …)
Tag:            vX.Y.Z
Release:        <URL>
Image:          <registry>/<image>:X.Y.Z@sha256:…
Nächster Schritt: Im deployments-Repo für die betroffenen Instanzen eintragen
                  und /deploy-check fahren.
```

Zusätzlich nennen, was in diesem Release eine Migration oder eine ENV-Änderung mitbringt —
das entscheidet, ob ein Update von Hand begleitet werden muss.
