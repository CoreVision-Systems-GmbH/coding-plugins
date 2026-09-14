# Was und Warum

<!-- Was ändert sich aus Sicht eines Nutzers? Warum? Wenn es ein Issue gibt: "Schließt #123". -->

**Was:**

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

# Migration und ENV-Änderung

<!-- "keine" ist eine gültige Antwort. -->

- **Migration:** keine / additiv / nicht additiv (Wartungsfenster nötig)
- **Neue oder geänderte ENV-Schlüssel:** keine / …
- **Handgriff beim Update nötig:** nein / ja — welcher:

# Definition of Done

Nur ankreuzen, was belegt ist.

- [ ] Funktion umgesetzt und geprüft — automatisiert und auf dem manuellen Weg
- [ ] Formatter, Linter, Statik, Tests, Build lokal grün, mit Ausgabe belegt
- [ ] `CHANGES.md` unter „Unveröffentlicht" ergänzt
- [ ] README oder ADR nachgezogen, falls Betrieb oder Richtung betroffen sind
- [ ] Diff sauber: keine fremden Änderungen, keine Debug-Reste, keine Secrets
- [ ] `docs/status.md` aktuell
- [ ] CI grün
- [ ] Bei Live-Projekten: ausgerollt und auf der Ziel-URL geprüft
