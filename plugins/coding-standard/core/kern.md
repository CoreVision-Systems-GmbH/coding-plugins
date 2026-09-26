# Firmenstandard — Kern

Gilt in jedem Repo, das den Standard erklärt (`coding-standard@corevision` in `.claude/settings.json`).
Rangfolge bei Widerspruch: ausdrückliche Anweisung des Nutzers > `CLAUDE.md` und `.claude/rules/` des Repos > Stack-Overlay > dieser Kern. Wer einen Widerspruch findet, meldet ihn als Issue im Standard-Repo; bis zur Entscheidung gilt die strengere Auslegung. Eine Regel, die im Weg steht, wird nicht gebrochen, sondern gemeldet.
Was nicht verhandelbar ist (Push auf `main`, Force-Push, Secrets im Repo), setzen Hook, CI und Rulesets durch — dieser Text erinnert nur daran.
**muss** ist Pflicht, eine Abweichung ist ein Mangel. **soll** ist der Regelfall, eine Abweichung wird im PR begründet. **kann** ist frei. Was hier ohne Zusatz steht, ist ein Muss; ein Repo weicht davon nur bewusst ab — in `CLAUDE.md` oder `.claude/rules/` mit einer ADR und Freigabe, entsprechend der Rangfolge oben —, nie durch einen stillen Diff.

## Fünf Sätze, die alles tragen
1. **Denken vor Code.** Aufgabe verstehen, Annahmen nennen, Unklares fragen, dann erst schreiben.
2. **Bauen ist nicht prüfen.** Wer baut, prüft nicht sich selbst; grün ist erst, was Werkzeug und ein frischer Blick quittiert haben.
3. **Beweis statt Behauptung.** Grün ist nur, was in diesem Zustand lief, belegt mit der Ausgabe; was nicht geprüft wurde, wird benannt.
4. **Nie direkt auf `main`.** Zweig, PR, grüne Prüfstrecke; in Produktion nur ein getaggtes Release, und nur auf Auftrag.
5. **Ein Mensch gibt frei.** Maschinen-Grün ist notwendig, nicht hinreichend; die Freigabe trifft, wer den Unterschied gesichtet hat.

## Denken vor Code
- Aufgabe in eigenen Worten: Ziel, sichtbares Ergebnis, **Abnahmekriterien nummeriert (A1…An), jedes mit der Invariante, die erhalten bleiben muss** („fertig, wenn X funktioniert und die Mandantentrennung unverändert ist“), und **was nicht dazugehört**. Mehrdeutiges fragen, nicht annehmen; Fragen bündeln.
- Annahmen nennen. Mehrere Deutungen → vorlegen. Einfacheren Weg gesehen → sagen. Wächst der Auftrag, anhalten und den Umfang neu bestätigen.
- Kleine Änderung: drei Zeilen Plan im Chat, dann los. **Plan Mode mit Freigabe**, wenn Datenmodell, Berechtigungen, Mandanten, Anmeldung, Architektur oder Lieferweg berührt sind oder sich die Änderung nicht in einem Satz als Diff beschreiben lässt. Der Plan nennt Schritte mit je einer Prüfung, „Nicht Teil davon“ und den Rückweg.
- Zu Beginn einer Aufgabe lesen: `CLAUDE.md`, `CHANGES.md` („Unveröffentlicht“), `docs/status.md`, die letzten Commits, offene PRs und Issues zum Thema. Projektbefehle **und Zieldatenbank** aus `CLAUDE.md` übernehmen, nie erfinden.
- Vor der ersten Änderung laufen alle Prüfungen einmal auf dem unveränderten Stand. Erst wenn sie grün sind, beginnt die Arbeit; sonst ist später nicht zu unterscheiden, was von dir kommt.
- Technische Detailentscheidungen selbst treffen und kurz begründen. **Anhalten und vorlegen** bei Kunde, Geld, Sicherheit, Daten, Architektur, Datenbankschema, Mandanten, Anmeldung und Rechten. Rückfrage nur bei Fachlogik, Irreversiblem oder Mehrdeutigem; sonst die Default-Annahme in einem Satz nennen und weiterarbeiten.

## Umsetzen
- Nur, was beauftragt ist: keine Abstraktion für Einmal-Code, keine „Verbesserung“ fremder Zeilen. Jede geänderte Zeile führt auf ein Abnahmekriterium zurück; was außerhalb auffällt, wird genannt, nicht umgesetzt.
- Konventionen des Repos, auch wenn du es anders machen würdest. Kürzeste klare Lösung.
- Funktionen bleiben klein: höchstens 50 Anweisungen, zyklomatische Komplexität 10, Verschachtelung 4, Dateien 800 Zeilen — was darüber liegt, wird zerlegt, nicht kommentiert. Die Werkzeuge je Stack melden, was sie messen (ruff: Komplexität, Verzweigungen, Anweisungen; PHPMD: dazu Methoden- und Klassenlänge; ESLint: alle vier): bis Ende 2026 als Warnung, ab 2027-01-01 als Tor.
- **Diagnose vor Reparatur.** Bei jedem Fehler zuerst die Ursache am echten Verhalten nachweisen (Log, Reproduktion, Probe), dann der Test, der sie zeigt, dann der Fix; geht der Test nicht sinnvoll, steht das Warum im PR. Ein Fix ohne Diagnose ist geraten. Nach zwei Versuchen ohne Fortschritt ist nicht die Lösung falsch, sondern die Anforderung unklar: Ansatz verwerfen, Auftrag prüfen.
- Vor einem Umbau ohne Verhaltensänderung entsteht ein Charakterisierungstest, der das heutige Verhalten festhält; der PR belegt gleiche Eingabe → gleiches Ergebnis. Ohne diesen Beleg ist ein Refactoring nicht fertig.
- **Datenbank ist PostgreSQL** (Hauptversion der Vorlage, heute 18), auch für kleine interne Dienste. Einzige Ausnahme im Standard ist MariaDB für WordPress. SQLite nur als Testdatenbank im PR-Lauf und in Skripten ohne Dienst. Jede andere Datenbank braucht eine ADR im Projekt; im Bestand wird sie beim nächsten größeren Umbau abgelöst.
- Fehler ausdrücklich behandeln; Eingaben an Systemgrenzen validieren. Anzeige ausblenden und Bedienung sperren sind Bequemlichkeit — **nur der Server, der die Anfrage abweist, schützt.** Berechtigungen serverseitig, objektbezogen und bei Mandanten zentral am Modell.
- Alle Texte Deutsch mit echten Umlauten — Oberfläche, Kommentare, Commits, PRs, Doku. Bezeichner sind Englisch und ASCII; Datei- und Branch-Namen, URLs, Schlüssel und Commit-Typen sind ASCII. Deutsche Fachbegriffe in Bezeichnern nur, wenn sie im Glossar der `CLAUDE.md` stehen — als ASCII-Wort in Code und Datenbank, in der Oberfläche mit Umlaut; das Glossar nennt beide Schreibweisen.
- Kommentare erklären das Warum. Vorfälle werden datiert festgehalten („Am 2026-08-18 genau so passiert: …“), bewusste Nicht-Entscheidungen begründet, damit niemand sie beim Aufräumen „nachrüstet“.
- Keine Secrets in Code, Commits, Logs oder Tests. `.env` bleibt lokal, `.env.example` ist das Schema mit Kommentar je Schlüssel. Ist ein Geheimnis in Commit, Log oder Chat geraten, wird es gewechselt — Entfernen allein genügt nicht — und geprüft, ob es über einen Abgleich abgeflossen ist. Ein gemeldeter Fehler ist ein Vorfall, ein verschwiegener ein Vertrauensbruch.
- Nach jedem Teilschritt, bevor der nächste beginnt: Syntax und Formatter auf der Datei · Abgleich gegen Auftrag und Regeln · Spaltennamen gegen das echte Schema, nicht gegen den Code · bei Umbau Verhaltensgleichheit vorher/nachher · die vier Grenzfälle **leer, sehr viele Datensätze, Sonderzeichen und Umlaute, fehlende Berechtigung** · Rückmeldung mit Datei:Zeile und offenen Annahmen.

## Bauen ist nicht prüfen
- Tests: Feature vor Unit; Rechte paarweise (erlaubt **und** verweigert); bei Mandanten die Kreuzprobe (A liest B → Abweisung, nicht leere Liste); End-to-End nur für kritische Wege; kein Prozentziel auf den Bestand. **Der Test einer Sicherung stellt die Gefahr her** — das belegte Feld, die zu große Datei, die fremde Kennung; wer nur den Normalfall prüft, hat die Sicherung nicht geprüft. Jeder Fix und jedes Feature bringt einen Test mit, der ohne die Änderung rot wäre.
- Befunde haben Fristen: KRITISCH (Ausfall, Datenverlust, ausnutzbare Lücke) 24 Stunden · HOCH vor dem Release, spätestens eine Woche · MITTEL ein Monat · HINWEIS nächstes Release — in den Agents CRITICAL, HIGH, MEDIUM, LOW. Bekannte Schwachstellen in Abhängigkeiten: 72 Stunden, kritische 24 — Sicherheits-Bumps sofort, nicht im Wochentakt; Versionssprünge zuerst auf dem Dev-Server, dann in Produktion.
- Befunde, die nicht sperren, stehen in `docs/status.md` unter „Rückstände“ mit Termin — nicht im Chat, nicht im Gedächtnis.

## Beweis statt Behauptung
- Die Projektbefehle laufen lassen: Formatter, Linter, Statik, Tests, Build. „Grün“ ist nur, was in diesem Zustand lief; Ausgabe kurz zitieren; **„nicht geprüft“ ausdrücklich benennen**.
- Jedes Repo fasst diese Prüfungen in **einem** Befehl zusammen — je Stack einer: `composer check` (Laravel, WordPress), `npm run check` (Astro), `bash scripts/check.sh` (FastAPI, Script) —, und die `CLAUDE.md` nennt ihn als erste Zeile unter „Befehle“. Er läuft vor jedem Commit; die CI führt dieselben Schritte aus, damit lokal und dort nichts auseinanderläuft.
- Oberflächen-Änderungen zusätzlich im Browser prüfen, mindestens den geänderten Weg.

## Arbeiten mit KI
- Wer baut, prüft nicht sich selbst: Vor „Ready for review“ läuft ein Review in frischem Kontext (Subagent oder zweites Modell), nur auf Korrektheit, Sicherheit und Scope-Treue — keine Geschmacksfragen. Bei Anmeldung, Rechten, Datenbank und Mandanten läuft zusätzlich der `security-reviewer`. Die prüfende KI ändert nichts; sie misst, meldet und schlägt vor. Einzige Ausnahme ist der `build-fixer`, und der behebt nur, was rot ist.
- Bei Änderungen an Rechten, Schema, Mandanten, Anmeldung, Geld oder bei vollständig KI-erzeugtem Bestand prüft zusätzlich ein zweites Modell oder ein zweiter Mensch. Weichen die Urteile ab, gilt das schärfere; der PR vermerkt „Sichtung durch einen Menschen empfohlen“.
- Was an einen KI-Dienst darf: Quellcode ohne Geheimnisse und Testdaten mit Platzhaltern → ja. Geheimnisse, `.env`, Schlüssel → nie. Personenbezogene Daten, echte Kundendaten, Auszüge aus Produktionsdatenbanken → nie an ein Cloud-Modell; an ein lokales Modell nur, wenn der Vertrag es deckt. Lässt sich das nicht sicherstellen, prüft ein Mensch.
- Recherche, Reviews und unabhängige Teilaufgaben an Subagenten, parallel wo möglich, in getrennten Dateibereichen — nie zwei an derselben Stelle. Ergebnisse zusammenfassen, nicht durchreichen.
- Das persönliche Gedächtnis von Claude behält nur, was zur Person gehört. Alles zum Projekt (Fallen, Pausenstände, Entscheidungen, bestätigte Schnittstellen) steht in `CLAUDE.md`, `docs/status.md` oder einer ADR. Was aus Code, Git-Log oder Doku ableitbar ist, wird nirgends zweitgespeichert.
- Neben dem Firmenstandard läuft keine fremde Sammlung von Agents, Skills oder Regeln, die nicht gelesen und per ADR aufgenommen wurde. Fremde Agent-Dateien sind Anweisungen, die Claude ausführt.
- Hat das Produkt selbst eine KI-Funktion, ist sie in der Oberfläche gekennzeichnet, und die eingesetzten Modelle stehen in `docs/ki-modelle.md` mit Risikoklasse und Rolle (Anbieter oder Betreiber).

## Git & Lieferung
- Nie direkt auf `main`. Branch `feat/…`, `fix/…`, `chore/…`, `docs/…` (kebab-case, ASCII); früh ein Draft-PR mit gefüllter Vorlage — die CI prüft sie (Abnahmekriterien, Prüfweg, „Nicht geprüft“, Rückweg); Squash-Merge nur bei grüner CI. Ein Anliegen je Commit, ein Thema je PR; über etwa 400 geänderte Zeilen wird gestapelt oder die Größe im PR begründet.
- Conventional Commits: Typ englisch, Text deutsch; der Body erklärt das Warum und nennt die verworfene Alternative, wenn es eine gab. Kein Force-Push auf geteilte Branches. Dateien mit exaktem Pfad stagen — kein `git add .`, kein `-A`: So landen `.env`, Dumps und Diagnoseskripte nicht im Repo. Prüfhooks (Geheimnis-Scanner gitleaks vor jedem Commit und in der CI) werden nicht umgangen (`--no-verify`, `core.hooksPath`): Ein Befund wird behoben, nicht übersprungen.
- **Der PR ist die Lieferung.** Was nicht dort liegt, ist nicht geliefert — keine Archive, keine Mail, keine Kopien in privaten Konten. Code liegt in `~/Code`, nie in OneDrive, Dropbox oder iCloud.
- Versionen `vX.Y.Z` über `/release`; Images entstehen aus dem Tag, nie `latest` in Produktion. Kundeninstanzen nur über Release + `deploy/update.sh` nach Freigabe; interne Live-Systeme zeitnah nachziehen. Vor jedem Ausrollen den Server-Stand gegen das Repo prüfen.
- Lieferweg mit Server-Baustein: entwickelt und getestet wird auf dem Dev-Server (`deploy/dev.sh up`, `https://dev.<domain>`, nur im Tailnet); nach Abnahme PR, Merge, Release; auf den Prod-Server kommt ein Release nur per `rollout` — sofort oder zum Termin, nach Freigabe (`/rollout`). Docker auf dem eigenen Rechner nur im Notfall.
- Migrationen additiv (erst erweitern, später entfernen); Backup vor jeder Migration in Produktion.
- Merge, Release, Rollout, Löschen und alles Produktionswirksame nur nach ausdrücklicher Bestätigung — Bedenken einmal nennen, dann ausführen. Commit und Push auf den eigenen Zweig sind Routine.

## Dokumentation & Kontext
- `CHANGES.md` (Keep a Changelog, Deutsch, aus Nutzersicht) bei jeder nutzerrelevanten Änderung; README bei Betriebs- oder Verhaltensänderung; Richtungsentscheide als ADR in `docs/decisions/`; `docs/status.md` an Checkpoints fortschreiben.
- Bei etwa 75 % Kontext: hinweisen, `docs/status.md` schreiben, Neustart oder `/compact` vorschlagen.

## Definition of Done
Freigegeben hat ein Mensch, der den Unterschied und die Abschlusszeilen gesichtet hat. Bei Ein-Personen-Repos ist das die eigene Durchsicht; ab der zweiten Person gilt Review-Pflicht 1. Auch bei grüner Prüfstrecke darf er ablehnen.
1. Umgesetzt und geprüft — automatisiert und auf dem manuellen Weg; jedes Abnahmekriterium hat einen Nachweis.
2. Projektprüfungen grün, mit Ausgabe belegt.
3. `CHANGES.md` aktualisiert (README/ADR, wenn betroffen); `docs/status.md` aktuell.
4. PR reviewbar: sauberer Diff, Vorlage gefüllt, CI grün.
5. Bei Live-Systemen ausgerollt und geprüft — Kundeninstanzen nach Freigabe über den Standardweg.

Bei einem PR endet die Arbeit mit vier Zeilen: Geändert (mit A1…An) · Geprüft (Befehl → Ergebnis) · Nicht geprüft / Risiken · Offen.
