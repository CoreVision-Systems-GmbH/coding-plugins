# Vorfall-Runbook

Gilt für Sicherheitsvorfälle, Datenschutzverletzungen und ausgenutzte Schwachstellen in allem,
was CoreVision Systems entwickelt oder betreibt — für alle, die daran arbeiten, auch Externe.
Stand der Rechtslage: 2026-09-26. Keine Rechtsberatung; im Zweifel melden und nachfragen.

| Rolle | Wer |
|---|---|
| Verantwortlich (entscheidet über Meldungen, informiert Kunden, führt das Protokoll) | Geschäftsführung |
| Meldeweg nach innen | `security@cvsystems.ai`; wenn es eilt, zusätzlich telefonisch über die Nummer der Geschäftsführung aus Projektvertrag oder Firmenablage |
| Eingang für Meldungen von außen | `security@cvsystems.ai` |

## 1. Sofort — wer etwas bemerkt

1. **Der Geschäftsführung melden, sofort** — auch am Abend und am Wochenende, lieber einmal zu
   viel. Ein gemeldeter Fehler ist ein Vorfall, ein verschwiegener ein Vertrauensbruch (Kern).
2. **Zeitpunkt der Kenntnis notieren**, mit Datum, Uhrzeit und Zeitzone. Ab da laufen die
   Fristen unten.
3. **Nichts löschen, nichts still reparieren.** Logs sichern, bevor sie rotieren — per
   Umleitung in eine Datei der Firmenablage (`docker compose logs --no-color > …`,
   `docker logs edge-caddy > …`), **nie in einer KI-Session ausgeben**: Logs enthalten
   personenbezogene Daten (Kern, „Arbeiten mit KI“). Dann erst eindämmen.

## 2. Einordnen — in der ersten Stunde

| Frage | Wenn ja |
|---|---|
| Sind personenbezogene Daten betroffen (gelesen, verändert, verloren, abgeflossen)? | Abschnitt 4 (DSGVO) |
| Betreiben wir die Instanz für einen Kunden? | Wir sind Auftragsverarbeiter: den Kunden informieren, er meldet (Abschnitt 4) |
| Wird eine Schwachstelle in einem Produkt, das wir unter unserem Namen auf den Markt gebracht haben oder bringen, aktiv ausgenutzt, oder berührt ein schwerer Vorfall dessen Sicherheit? | Abschnitt 3 (CRA) — wir melden als Hersteller |
| Ist der Kunde eine NIS2-Einrichtung (wesentlich oder wichtig)? | Abschnitt 5 — er meldet, wir liefern zu |

**Wer meldet nach dem CRA?** Hersteller ist, wer das Produkt unter eigenem Namen oder eigener
Marke vermarktet. Läuft eine Anwendung unter dem Namen des Kunden, meldet der Kunde; wir
informieren ihn unverzüglich und liefern zu wie in Abschnitt 5. Ob eine Anwendung überhaupt ein
„Produkt mit digitalen Elementen“ ist, ist eine Einzelfallfrage (Leitlinie der Kommission
C(2026) 5252): installierbare Software und Apps samt ihrem Backend meist ja, eine reine
Web-Anwendung oder SaaS meist nicht. **Im Zweifel entscheidet die Geschäftsführung — eher
melden:** Eine unnötige Frühwarnung schadet nicht, eine versäumte schon.

## 3. CRA — wir als Hersteller (Meldepflicht seit 11.09.2026)

| Fall | Frühwarnung | Meldung | Abschlussbericht |
|---|---|---|---|
| Aktiv ausgenutzte Schwachstelle | unverzüglich, spätestens 24 h nach Kenntnis | spätestens 72 h nach Kenntnis | spätestens 14 Tage, nachdem eine Korrektur oder Abhilfe verfügbar ist — auch ein Workaround zählt |
| Schwerwiegender Sicherheitsvorfall | unverzüglich, spätestens 24 h nach Kenntnis | spätestens 72 h nach Kenntnis | spätestens 1 Monat nach der Meldung |

- **Wohin:** ENISA Single Reporting Platform, <https://portal.cra-srp.enisa.europa.eu/> — die
  Meldung geht zugleich an CERT.at, das Koordinator-CSIRT für Österreich. Zugang mit EU Login
  und Mehrfaktor-Anmeldung, nur mit Firmenadresse. Fällt die Plattform aus: CERT.at direkt
  kontaktieren und die Meldung auf der Plattform nachholen.
- **Nutzer informieren:** Betroffene Nutzer erfahren von der Schwachstelle oder dem Vorfall und
  von der Abhilfe (Art. 14 Abs. 8).
- **Nach der Behebung** (Pflicht ab 11.12.2027, bei uns ab sofort): die behobene Schwachstelle
  mit Beschreibung, Schwere und Abhilfe in den Release-Notizen nennen (`CHANGES.md`, Abschnitt
  „Sicherheit“) — **erst, wenn die betroffenen Instanzen aktualisiert sind** oder die Nutzer
  Zeit hatten zu patchen. Einzelheiten vorher helfen nur Angreifern.

## 4. DSGVO — Verletzung des Schutzes personenbezogener Daten

**Instanz für einen Kunden (wir sind Auftragsverarbeiter):** den Kunden **unverzüglich**
informieren (Art. 33 Abs. 2) — er ist Verantwortlicher und meldet selbst. Mitliefern, was er für
seine Meldung braucht: Art der Verletzung, Kategorien und ungefähre Zahl der Betroffenen und
Datensätze, wahrscheinliche Folgen, ergriffene und geplante Maßnahmen, Ansprechpartner.

**Eigene Daten (wir sind Verantwortlicher):** Meldung an die Datenschutzbehörde unverzüglich,
möglichst binnen 72 Stunden nach Bekanntwerden (Art. 33 Abs. 1); kommt sie später, mit
Begründung der Verzögerung. Weg: Onlineformular der Datenschutzbehörde
(<https://dsb.gv.at/eingabe-an-die-dsb/-meldung-data-breach>) oder `dsb@dsb.gv.at`. Bei
voraussichtlich hohem Risiko auch die Betroffenen unverzüglich benachrichtigen (Art. 34). Keine
Meldung nötig, wenn voraussichtlich kein Risiko besteht — dokumentiert wird trotzdem jede
Verletzung (Art. 33 Abs. 5).

## 5. NIS2 — Kunden als Einrichtungen

Ab 01.10.2026 gilt in Österreich das NISG 2026: Bei einem erheblichen Sicherheitsvorfall
Frühwarnung binnen 24 h, Meldung binnen 72 h, Abschlussbericht 1 Monat nach der Meldung — an
das zuständige CSIRT (das sektorale, sonst das nationale; übergangsweise CERT.at). Die Pflicht
trägt die Einrichtung, also der Kunde. Wir informieren ihn **unverzüglich** und liefern die
Fakten so, dass er die 24 Stunden halten kann.

## 6. Eindämmen und beheben

- Betroffene Zugänge sperren, Geheimnisse wechseln — ein Geheimnis, das abgeflossen sein kann,
  gilt als verbrannt (Kern). Sicherung vor jedem Eingriff in eine Produktion.
- Die Korrektur geht den normalen Weg: Zweig, PR, Release, Rollout — im Notfall schnell, aber
  mit Tag und Rückweg. Kein Einzelpatch am Server vorbei.
- Jede Korrektur bringt einen Test mit, der die Lücke nachstellt und ohne die Änderung rot wäre.

## 7. Abschluss

- Abschlussberichte fristgerecht (Abschnitt 3 und 5).
- Nachbesprechung: Ursache, warum nicht früher erkannt, welche Prüfung künftig anschlägt — als
  Regel im Standard, als Test oder als ADR im Projekt.
- Das Protokoll liegt in der Firmenablage der Geschäftsführung, **nie in einem Repository**: Es
  enthält Namen, Kundendaten und Einzelheiten der Lücke.

## Vorfallprotokoll

```text
Kenntnis am:       JJJJ-MM-TT hh:mm (Zeitzone), durch:
Betroffen:         Produkt / Instanz / Kunde, Fassung
Art:               Schwachstelle ausgenutzt / Vorfall / Datenschutzverletzung
Personenbezug:     ja / nein — Kategorien, ungefähre Zahl
Unsere Rolle:      Hersteller (CRA) / Verantwortlicher / Auftragsverarbeiter / Zulieferer des Kunden
Meldungen:         an wen, wann (Frühwarnung, Meldung, Abschluss), Aktenzeichen
Kunden informiert: wer, wann, wie
Maßnahmen:         eingedämmt am, behoben mit Fassung, Geheimnisse gewechselt
Abschluss:         Datum, Ursache, Folgemaßnahme
```

## Vorbereitung und Übung

Damit die Fristen im Ernstfall zu halten sind, braucht es vorher:

- ein Postfach oder einen Alias `security@cvsystems.ai`, den die Geschäftsführung liest,
- ein EU-Login-Konto mit Mehrfaktor-Anmeldung für die Meldeplattform, auf eine Firmenadresse,
- je Instanz den Ansprechpartner des Kunden für Sicherheitsvorfälle (Firmenablage),
- eine benannte Vertretung der Geschäftsführung.

Einmal im Jahr wird ein Vorfall am Tisch durchgespielt: Wer erfährt es wann, wer meldet was,
halten die Fristen? Stand der Vorbereitung und Datum der letzten Übung hält die
Geschäftsführung fest.
