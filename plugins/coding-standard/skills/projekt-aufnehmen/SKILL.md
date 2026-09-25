---
name: projekt-aufnehmen
description: Bestehendes Projekt, das nicht mit /projekt-neu entstanden ist, in den Firmenstandard aufnehmen — Bestandsaufnahme in vier Stufen, Erklärung und Kontext-Dateien anlegen (nie überschreiben), ADR mit den Lücken, PR. Kein Umbau des Codes. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: [pfad]
---

# /projekt-aufnehmen — bestehendes Projekt in den Firmenstandard aufnehmen

Pfad aus dem Aufruf (falls angegeben): `$ARGUMENTS` — sonst das aktuelle Arbeitsverzeichnis.

Gegenstück zu `/projekt-neu` für Repos mit eigener Geschichte. Nichts wird umgebaut: Der
Standard verlangt die Regeln des Kerns, keine Ordnerstruktur; das Overlay gilt sinngemäß, und
was abweicht, wird aufgeschrieben. Der Standard ist eine Leiter mit vier Stufen — das Skript
`${CLAUDE_PLUGIN_ROOT}/scripts/projekt-aufnehmen.sh` erledigt die ersten zwei deterministisch
und berichtet die anderen zwei:

| Stufe | Was | Wer |
|---|---|---|
| 0 Erklärung | `.claude/settings.json` (installiert das Plugin für jeden, der das Repo öffnet); bei Stacks ohne Markerdatei `.coding-standard` | Skript |
| 1 Kontext | die gemeinsamen Dateien aus `templates/repo`: `CLAUDE.md` mit den echten Befehlen des Repos, `CHANGES.md`, `docs/status.md`, ADR „Aufnahme in den Firmenstandard“ mit den Lücken, PR-Vorlage, CODEOWNERS, CI-Durchsicht, Dependabot, pre-commit-Hook mit gitleaks samt `.gitleaks.toml` (setzt `core.hooksPath`), `.claude/rules` des Stacks | Skript, du prüfst nach |
| 2 Lieferweg | Dockerfile, Compose, `deploy/`, `release.yml` | eigener PR, später |
| 3 Betriebsvertrag | Fassung im Produkt, Health, TrustProxies, Prüfbefehle, Qualitätsgates — je Stack aus dem Overlay | eigene PRs, wenn der Bereich ohnehin angefasst wird |

Erfinde nichts. Was du nicht weißt, fragst du — einmal, gebündelt.

## 1. Bestandsaufnahme

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/projekt-aufnehmen.sh --dir <pfad>
```

Liest nur und ändert nichts. Zitiere Kopf und Zusammenfassung wörtlich; die Lücken je Stufe
fasst du in einem Satz zusammen. Ist der Arbeitsbaum nicht sauber oder der Zweig `main`: sag
es — die Aufnahme kommt auf einen eigenen Zweig, und `--apply` verlangt einen sauberen Baum.

Erkennt das Skript keinen Stack (Werkzeuge ohne Framework), gehört `--stack <name>` dazu —
die Namen kennt `scripts/projekt-neu.sh --list-stacks`. Bei Next.js gilt das Ausnahme-Overlay;
es gibt kein Register, die Aufnahme legt nur Kern-Dateien an.

## 2. Ein gebündeltes Interview

Ein `AskUserQuestion` mit höchstens vier Fragen — nur, was das Skript nicht selbst weiß:

| Frage | Optionen |
|---|---|
| **Zweck** | Vorschlag aus der README als erste Option; eigener Text über „Other“. Zwei Sätze: was es tut, für wen. Geht in `CLAUDE.md` und die ADR. |
| **Firma / GitHub-Eigentümer** | aus `origin` vorbelegt (erste Option), sonst wie in `/projekt-neu`. Bestimmt auch `--company` für `LICENSE`. |
| **Kunde/Instanz** | „intern“ oder frei, z. B. „Musterkunde auf host1“. |
| **Umfang** | „Stufe 0 und 1 jetzt, Lücken als ADR (empfohlen)“ · „nur Bestandsaufnahme, nichts anlegen“ |

## 3. Zusammenfassung und Freigabe

Sechs Zeilen: Name · Stack · Eigentümer · Ordner · Kunde · was angelegt wird (Anzahl der
fehlenden Dateien aus Stufe 0 und 1). Warte die Bestätigung ab. Erst danach schreibt etwas.

## 4. Anlegen

```bash
cd <pfad> && git checkout -b chore/firmenstandard-aufnahme
bash ${CLAUDE_PLUGIN_ROOT}/scripts/projekt-aufnehmen.sh --dir <pfad> --apply \
  --owner <owner> --purpose "<zweck>" [--customer "<kunde>"] [--company "<firma>"] \
  [--stack <name>] [--vault <pfad>]
```

Das Skript legt nur an, was fehlt, überschreibt nie und bricht ab, wenn der Arbeitsbaum nicht
sauber ist. `--vault` nur, wenn der Vault auf diesem Rechner liegt. Zitiere die Liste der
angelegten Dateien. Bricht das Skript ab, gib die Meldung wörtlich weiter und behebe die
Ursache — ein zweiter Lauf ist gefahrlos, er legt nur an, was noch fehlt.

## 5. Nacharbeit — die macht Claude, jede mit Prüfung

Die Session läuft nicht im aufgenommenen Ordner — jeden Befehl mit `cd <pfad> && …`.

- [ ] `CLAUDE.md`: Die Befehlstabelle stammt aus `composer.json`, `package.json` und
      `Makefile` — Zweck-Spalte in Worten ausfüllen, Unwichtiges streichen (`post-*`-Hooks sind
      schon draußen), **Karte** aus der Ablage des Repos, **Fallen** aus README und Erfahrung.
      Nichts erfinden: jeden Befehl, der stehen bleibt, einmal laufen lassen.
- [ ] ADR `docs/decisions/NNNN-aufnahme-firmenstandard.md`: Die Lücken aus Stufe 2 und 3
      stehen unter „Zu tun“. Verschiebe nach „Bewusst so belassen“, was mit Grund anders bleibt
      (eigener Health-Pfad, andere Ordnerstruktur, kein Abbild, weil nicht von uns betrieben) —
      mit dem Grund. Der Rest bleibt „Zu tun“.
- [ ] `docs/status.md`: „Stand“ in ganzen Sätzen (was läuft wo, welche Fassung), „Nächste
      Schritte“ in sinnvoller Reihenfolge.
- [ ] `CHANGES.md`, falls es sie schon gab: Abschnitt „Unveröffentlicht“ nach Keep a Changelog
      anlegen, darunter „In den Firmenstandard aufgenommen“.
- [ ] Markerdatei `.coding-standard`: Erkennt der Hook den Stack selbst (`laravel`, `fastapi`,
      `astro`, `wordpress`), ist sie neben `settings.json` überflüssig — entfernen. Bei `script`
      bleibt sie.
- [ ] Die Prüfbefehle aus der neuen `CLAUDE.md` einmal laufen lassen und die letzten Zeilen
      zitieren. Die Aufnahme ändert keinen Code — aber `tests.yml` läuft ab jetzt bei jedem PR
      und muss grün sein; ist sie es nicht, ist das der erste Punkt in `docs/status.md`, nicht
      ein Grund, den Workflow zu entfernen.

Dann PR (Vorlage füllen; „Nicht Teil davon: Stufe 2 und 3, siehe ADR“), CI abwarten,
Squash-Merge — nie direkt auf `main`:

```bash
cd <pfad> && git add -A && git commit -m "chore: Aufnahme in den Firmenstandard (Stack <stack>)"
git push -u origin chore/firmenstandard-aufnahme
gh pr create --fill
gh pr checks --watch
gh pr merge --squash --delete-branch
```

## 6. Stufe 2 und 3 — nicht in diesem Lauf

Jeder Punkt aus `docs/status.md` ist ein eigener PR mit Plan Mode (der Lieferweg ist
berührt): Vorlage aus `${CLAUDE_PLUGIN_ROOT}/templates/<stack>/dateien/`, Regel aus dem
Overlay, Abschnitt „Betriebsvertrag“. Reihenfolge, wenn nichts dagegen spricht: Fassung im
Produkt → Health → `release.yml` und `deploy/` → Backup → Qualitätsgates. Nichts davon muss am
Stück geschehen — aber alles, was nicht geschieht, steht in der ADR mit Grund.

### Statik im Bestand: Baseline mit Datum und Abbauplan

`/projekt-neu` verbietet Baselines — im Bestand sind sie der Weg, die Stufe sofort scharf zu
schalten, ohne den Merge zu blockieren: Larastan/PHPStan auf der Stufe des Standards (Laravel 8,
WordPress 6) mit `phpstan-baseline.neon`, im Kopf der Baseline Datum und Zahl der Befunde;
`docs/status.md` führt unter „Rückstände“ den Abbauplan mit Termin. Regel: Jede Datei, die ein PR
anfasst, verlässt die Baseline — der PR nimmt ihre Zeilen heraus und behebt die Befunde. Neuer
Code läuft nie gegen die Baseline. Dasselbe für `phpmd.xml`/ruff-Kennzahlen: die Warnphase bis
Ende 2026 gilt auch hier.

## 7. Abschluss

Angelegte Dateien, PR-Link, die offenen Punkte aus `docs/status.md`. Schließe mit:

> Claude jetzt in `<pfad>` neu starten — ab dann gilt der Standard automatisch.
