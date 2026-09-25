---
paths: ['tests/**']
---

# Tests

- **Feature vor Unit.** Der Wert liegt im durchlaufenen Weg: Route, Middleware, Policy,
  Action, Antwort. Unit-Tests nur für echte Logikkerne (Berechnung, Bewertung, Fristen).
- **Rechte immer paarweise.** Zu jedem „darf" gehört ein „darf nicht": erlaubt **und**
  verweigert, sichtbar **und** unsichtbar. Ein Policy-Test ohne Gegenprobe beweist nichts.
- **Keine Tests ohne Aussage.** Kein Test, der nur bestätigt, dass Laravel funktioniert;
  kein Abdeckungs-Prozentziel als Selbstzweck. Jeder Fix bringt einen Test mit, der ohne
  die Korrektur rot wäre — erst rot sehen, dann grün.
- **Gemessen wird der Diff, nicht der Bestand:** Die CI verlangt 80 % Abdeckung der neuen
  und geänderten Zeilen (diff-cover, bis Ende 2026 Warnung, ab 2027-01-01 rot). Nachts läuft
  `pest --mutate` (Schwelle 60, `mutates()` auf Actions und Services) und die Suite gegen
  PostgreSQL — Befunde als Rückstand mit Termin in `docs/status.md`.

## Konventionen dieses Repos

- Pest, Testnamen auf Deutsch: `it('sperrt den Außendienst aus der Verwaltung aus', …)`.
  Dateien in `tests/Feature` bzw. `tests/Unit`, benannt nach dem Fachthema.
- `declare(strict_types=1);` oben, darunter ein Blockkommentar, der erklärt, **welchen
  Fallstrick** die Datei offen hält.
- Gemerkte Singletons (Einstellungen, Zwischenspeicher) gehören in das `beforeEach` von
  `tests/Pest.php` zurückgesetzt — sonst trägt ein Test den Stand des vorigen mit sich.
- Die Suite läuft gegen **SQLite im Speicher**. Alles, was eine PostgreSQL-Eigenheit
  braucht (Volltext, PostGIS, `jsonb`-Operatoren), gehört hinter eine Weiche oder in einen
  eigenen Lauf — nicht in den Standarddurchgang.
- Filament-Tests brauchen PHP mit `intl`; ohne die Erweiterung enden sie mit HTTP 500.
- Larastan prüft `tests/` **nicht** (`phpstan.neon` listet nur den Anwendungscode), Pint
  dagegen schon. Formatfehler in Tests brechen also `composer test`.
- Zeit im Test festnageln (`travelTo`, feste Zeitzone), nie gegen `now()` ohne Bezug prüfen.
- **Mandanten: die Kreuzprobe ist Pflicht.** A liest B → Abweisung (403/404), nicht leere
  Liste; der Filter sitzt zentral am Modell (Global Scope, Tenancy), nie von Hand je Abfrage.
- **Testdatenbank fest verdrahtet:** `phpunit.xml` setzt `DB_CONNECTION=sqlite` und
  `DB_DATABASE=:memory:` mit `force="true"` — keine `.env` eines Entwicklers lenkt die Suite
  auf eine echte Datenbank. Kein rohes SQL in Migrationen; Dialekt-Weichen nur mit Begründung.
- **Synthetische Testdaten:** Factories mit Faker `de_AT`, Adressen nur `example.org` & Co.
  (gitleaks meldet echte Domänen und IBANs unter `tests/`), keine echt wirkenden Personen, nie
  ein Auszug aus Produktion.
- **Regressionsliste:** Jeder behobene Fehler wird ein benannter Dauerprüfpunkt — der Testname
  nennt Vorfall und Fassung: `it('rundet Beträge kaufmännisch (Vorfall 2026-09-25, v1.4.2)', …)`.
  Anlass: Release → alles; Hotfix → betroffener Block plus Regressionspunkte; Serveränderung →
  Rauchtest.
- **Grenzwerte selbst testen:** Bei `>= 18` prüft der Test 17, 18 und 19 — nicht 20. Eine
  Mutation `>=` → `>` fängt nur der Grenzwert; der nächtliche Mutationstest zeigt, wo das fehlt.

## Browser (tests/e2e, Playwright)

- **Gegen die Dev-Instanz, aus dem Tailnet:** `E2E_BASE_URL=https://dev.<APP_DOMAIN> npm run e2e`
  (einmalig `npx playwright install chromium`). Nicht aus der GitHub-CI — `dev.*` ist dort
  nicht erreichbar; Pest bleibt die Suite der CI.
- **Dieselbe Liste wie der Rauchtest:** `smoke.spec.ts` liest `deploy/smoke.txt` (Pfad, Status,
  Zeitbudget, Pflichtinhalt) und prüft dazu, was nur ein Browser sieht — Konsolenfehler,
  gescheiterte Anfragen. Eine Route gehört in `smoke.txt`, nicht in einen zweiten Test;
  Geschäftsflüsse (Anmeldung, Hauptvorgang) als eigene Spezifikation daneben.
- **Drei Viewports** (Desktop 1440, Tablet, Handy — alle mit Chromium, ein Browser genügt) — Filament und Inertia-Seiten brechen zuerst
  auf dem Handy. Ein Test läuft in allen drei Projekten.
- **Klick-Sweep** (`sweep.spec.ts`): jedem internen Link der Startseite folgen — kein 4xx/5xx,
  keine Konsolenfehler.
- **`retries: 0`.** Ein Test, der beim zweiten Mal grün wird, ist rot (flaky) und wird
  repariert, nicht wiederholt. Nachts auf dem Dev-Server `E2E_REPEAT=2`; Ergebnis als
  `tests/e2e/ergebnis.json`. Die Spezifikationen werden mit `tsc -p tests/e2e` typgeprüft
  (Teil von `types:check`).
