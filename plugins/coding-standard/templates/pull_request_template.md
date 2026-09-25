<!-- Die CI prüft diesen Text (scripts/pr-text-pruefen.sh): Abnahmekriterien mit Nachweis, ein
     Prüfweg mit Ergebnis, „Nicht geprüft“ und „Rückweg“ müssen gefüllt sein. Kommentare zählen nicht. -->

# Was und Warum

<!-- Was ändert sich aus Sicht eines Nutzers? Warum? Wenn es ein Issue gibt: "Schließt #123". -->

**Was:**

**Abnahmekriterien** — nummeriert, je mit Nachweis (Test, Datei:Zeile, Klickweg) und der
Invariante, die erhalten bleibt:

| Nr. | Kriterium | Nachweis |
|---|---|---|
| A1 |  |  |

**Warum:**

**Nicht Teil davon:**
<!-- Was bewusst offen bleibt, damit der Review nicht danach sucht. -->

# Prüfweg

**Automatisiert** — nur Befehle eintragen, die tatsächlich gelaufen sind, mit Ergebnis:

| Befehl | Ergebnis |
|---|---|
|  |  |

**Manuell** — der Klickweg, den ein Mensch nachgehen kann:

1.
2.

**Nicht geprüft:**
<!-- Ehrlich benennen. Lieber eine offene Lücke als ein stillschweigendes "passt". -->

# Risiko

<!-- Was kann kaputtgehen, wer merkt es zuerst, und wie kommt man zurück? -->

- **Auswirkung:**
- **Rückweg (Rollback):**

# Prüfprotokoll

<!-- Pflicht bei Rechten, Schema, Mandanten, Anmeldung, Geld oder Kundenauslieferung — sonst den
     Abschnitt löschen. Wer prüft, hat nicht gebaut: Subagent in frischem Kontext, zweites Modell
     oder ein Mensch. Soll = Anforderung, Ist = beobachtetes Verhalten, Beleg = Test, Ausgabe, Klickweg. -->

| Anforderung | Soll | Ist | Beleg |
|---|---|---|---|
| A1 |  |  |  |

- **Befunde:** keine / je Schwere (CRITICAL, HIGH, MEDIUM, LOW) mit Frist
- **Bewusst nicht getan:**
- **Gegenprüfung (zweites Modell oder zweiter Mensch):** stimmt überein / weicht ab — das schärfere Urteil gilt
- **Urteil:** FREIGEGEBEN / BEDINGT (Auflagen: …) / GESPERRT (Grund: …)

# Migration und ENV-Änderung

<!-- "keine" ist eine gültige Antwort. -->

- **Migration:** keine / additiv / nicht additiv (Wartungsfenster nötig)
- **Neue oder geänderte ENV-Schlüssel:** keine / …
- **Handgriff beim Update nötig:** nein / ja — welcher:

# Definition of Done

Nur ankreuzen, was belegt ist.

- [ ] Funktion umgesetzt und geprüft — automatisiert und auf dem manuellen Weg; jedes
      Abnahmekriterium hat einen Nachweis
- [ ] Formatter, Linter, Statik, Tests, Build lokal grün, mit Ausgabe belegt
- [ ] Review in frischem Kontext gelaufen; bei Anmeldung, Rechten, Datenbank oder Mandanten
      auch der Sicherheits-Review
- [ ] Bei Rechten, Schema, Mandanten, Anmeldung, Geld oder vollständig KI-erzeugtem Bestand:
      ein zweites Modell oder ein zweiter Mensch hat gegengeprüft — Prüfprotokoll gefüllt
- [ ] `CHANGES.md` unter „Unveröffentlicht" ergänzt
- [ ] README oder ADR nachgezogen, falls Betrieb oder Richtung betroffen sind
- [ ] Diff sauber: keine fremden Änderungen, keine Debug-Reste, keine Secrets
- [ ] `docs/status.md` aktuell
- [ ] CI grün
- [ ] Bei Live-Projekten: ausgerollt und auf der Ziel-URL geprüft
