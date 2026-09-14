# Firmenstandard — Kern

Gilt in jedem Repo, das den Standard erklärt (`coding-standard@corevision` in `.claude/settings.json`).
Rangfolge bei Widerspruch: ausdrückliche Anweisung des Nutzers > `CLAUDE.md` und `.claude/rules/` des Repos > Stack-Overlay > dieser Kern.
Was nicht verhandelbar ist (Push auf `main`, Force-Push, Secrets im Repo), setzen Hook, CI und Rulesets durch — dieser Text erinnert nur daran.

## Denken vor Code
- Aufgabe in eigenen Worten: Ziel, sichtbares Ergebnis, Akzeptanzkriterium und **was nicht dazugehört**. Unklares fragen, nicht annehmen; Fragen bündeln.
- Annahmen nennen. Mehrere Deutungen → vorlegen. Einfacheren Weg gesehen → sagen. Wächst der Auftrag, anhalten und den Umfang neu bestätigen.
- Kleine Änderung: drei Zeilen Plan im Chat, dann los. **Plan Mode mit Freigabe**, wenn Datenmodell, Berechtigungen oder Lieferweg berührt sind oder sich die Änderung nicht in einem Satz als Diff beschreiben lässt. Der Plan nennt Schritte mit je einer Prüfung, „Nicht Teil davon“ und den Rückweg.
- Zu Beginn einer Aufgabe lesen: `CLAUDE.md`, `CHANGES.md` („Unveröffentlicht“), `docs/status.md`, die letzten Commits, offene PRs und Issues zum Thema. Projektbefehle aus `CLAUDE.md` übernehmen, nie erfinden.
- Technische Detailentscheidungen selbst treffen und begründen; Richtungsentscheidungen (Kunde, Geld, Sicherheit, Daten) vorlegen.

## Umsetzen
- Nur, was beauftragt ist: keine Abstraktion für Einmal-Code, keine „Verbesserung“ fremder Zeilen. Jede geänderte Zeile führt auf den Auftrag zurück.
- Konventionen des Repos, auch wenn du es anders machen würdest. Kürzeste klare Lösung.
- Bugfix: zuerst der Test, der den Fehler zeigt. Geht das nicht sinnvoll, steht das Warum im PR.
- Fehler ausdrücklich behandeln; Eingaben an Systemgrenzen validieren; Berechtigungen serverseitig prüfen.
- Alle Texte Deutsch mit echten Umlauten — Oberfläche, Kommentare, Commits, PRs, Doku. ASCII/Englisch nur für Bezeichner, Datei- und Branch-Namen, URLs, Schlüssel, Commit-Typen.
- Keine Secrets in Code, Commits, Logs oder Tests. `.env` bleibt lokal, `.env.example` ist das Schema mit Kommentar je Schlüssel.
- Nach zwei gescheiterten Korrekturversuchen: Ansatz verwerfen, Ursache neu analysieren — nicht weiterflicken.

## Beweis statt Behauptung
- Die Projektbefehle laufen lassen: Formatter, Linter, Statik, Tests, Build. „Grün“ ist nur, was in diesem Zustand lief; Ausgabe kurz zitieren; **„nicht geprüft“ ausdrücklich benennen**.
- Oberflächen-Änderungen zusätzlich im Browser prüfen, mindestens den geänderten Weg.
- Tests: Feature vor Unit; Rechte immer paarweise (erlaubt **und** verweigert); End-to-End nur für kritische Wege; kein Prozentziel — aber jeder Fix und jedes Feature bringt einen Test mit, der ohne die Änderung rot wäre.

## Git & Lieferung
- Nie direkt auf `main`. Branch `feat/…`, `fix/…`, `chore/…`, `docs/…` (kebab-case, ASCII); früh ein Draft-PR mit gefüllter Vorlage; Squash-Merge nur bei grüner CI.
- Conventional Commits: Typ englisch, Text deutsch, ein Anliegen je Commit, der Body erklärt das Warum. Kein Force-Push auf geteilte Branches.
- Versionen `vX.Y.Z` über `/release`; Images entstehen aus dem Tag, nie `latest` in Produktion. Kundeninstanzen nur über Release + `deploy/update.sh` nach Freigabe; interne Live-Systeme zeitnah nachziehen. Vor jedem Ausrollen den Server-Stand gegen das Repo prüfen.
- Migrationen additiv (erst erweitern, später entfernen); Backup vor jeder Migration in Produktion.
- Destruktive oder produktionswirksame Aktionen nur nach ausdrücklicher Bestätigung — Bedenken einmal nennen, dann ausführen.

## Dokumentation & Kontext
- `CHANGES.md` (Keep a Changelog, Deutsch, aus Nutzersicht) bei jeder nutzerrelevanten Änderung; README bei Betriebs- oder Verhaltensänderung; Richtungsentscheide als ADR in `docs/decisions/`; `docs/status.md` an Checkpoints fortschreiben.
- Recherche, Reviews und unabhängige Teilaufgaben an Subagenten, parallel wo möglich; Ergebnisse zusammenfassen, nicht durchreichen.
- Vor „Ready for review“ ein Review in frischem Kontext — nur Korrektheit, Sicherheit, Scope-Treue; keine Geschmacksfragen.
- Bei etwa 75 % Kontext: hinweisen, `docs/status.md` schreiben, Neustart oder `/compact` vorschlagen.

## Definition of Done
1. Umgesetzt und geprüft — automatisiert und auf dem manuellen Weg.
2. Projektprüfungen grün, mit Ausgabe belegt.
3. `CHANGES.md` aktualisiert (README/ADR, wenn betroffen); `docs/status.md` aktuell.
4. PR reviewbar: sauberer Diff, Vorlage gefüllt, CI grün.
5. Bei Live-Systemen ausgerollt und geprüft — Kundeninstanzen nach Freigabe über den Standardweg.

Bei einem PR endet die Arbeit mit vier Zeilen: Geändert · Geprüft (Befehl → Ergebnis) · Nicht geprüft / Risiken · Offen.
