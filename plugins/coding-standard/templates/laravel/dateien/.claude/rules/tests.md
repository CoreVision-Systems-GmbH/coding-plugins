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
