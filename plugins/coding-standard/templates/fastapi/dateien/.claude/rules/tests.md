---
paths: ['tests/**']
---

# Tests

- **Gemessen wird der Diff, nicht der Bestand:** Die CI verlangt 80 % Abdeckung der neuen
  und geänderten Zeilen (diff-cover, bis Ende 2026 Warnung, ab 2027-01-01 rot). Nachts läuft
  `mutmut` über `app/modules` (Schwelle 60) — Befunde als Rückstand mit Termin in
  `docs/status.md`.

- **Feature vor Unit.** Der Wert liegt im durchlaufenen Weg: Route, Abhängigkeit,
  Autorisierung, Service, Antwort-Schema. Unit-Tests nur für echte Logikkerne.
- **Rechte immer paarweise.** Zu jedem „darf" gehört ein „darf nicht". Ein neuer Router
  ohne Test für den verweigerten Zugriff geht nicht durch den Review.
- **Fehlerpfade gehören dazu:** 401, 403, 404 und 422 sind Verhalten, nicht Zufall.
- **Keine Tests ohne Aussage.** Jeder Fix bringt einen Test mit, der ohne die Korrektur rot
  wäre — erst rot sehen, dann grün.

## Konventionen dieses Repos

- `pytest`, Testnamen auf Deutsch und in ganzen Aussagen:
  `def test_gruss_gibt_den_namen_zurueck(...)`.
- Jede Testfunktion hat `-> None`; `mypy --strict` prüft `app/`, und die Tests sollen
  denselben Anspruch erfüllen.
- Der `client`-Fixture aus `tests/conftest.py` benutzen. `TestClient(app)` **ohne** `with`
  führt weder `startup` noch `shutdown` aus — der Test prüft dann eine App, die es im
  Betrieb so nicht gibt.
- Zeit im Test festnageln, nie gegen `datetime.now()` ohne Bezug prüfen. Gespeichert wird
  immer mit Zeitzone (`datetime.now(timezone.utc)`).
- Konfiguration im Test ändern heißt: Umgebungsvariable setzen **und**
  `get_settings.cache_clear()` rufen — sonst hängt der alte Wert im Zwischenspeicher.
- **Mandanten: die Kreuzprobe ist Pflicht.** A liest B → 403/404, nicht leere Liste; der
  Filter sitzt zentral (Abhängigkeit, Repository), nie von Hand je Abfrage.
- **Synthetische Testdaten:** Faker `de_AT`, Adressen nur `example.org` & Co. (gitleaks meldet
  echte Domänen und IBANs unter `tests/`), keine echt wirkenden Personen, nie ein Auszug aus
  Produktion. Die Testdatenbank ist SQLite bzw. ein Fixture — nie die Datenbank aus der `.env`.
- **Regressionsliste:** Jeder behobene Fehler wird ein benannter Dauerprüfpunkt — der Testname
  nennt Vorfall und Fassung: `test_rundet_kaufmaennisch_vorfall_2026_09_25_v1_4_2`.
- **Grenzwerte selbst testen:** Bei `>= 18` prüft der Test 17, 18 und 19 — nicht 20. Eine
  Mutation `>=` → `>` fängt nur der Grenzwert; der nächtliche Mutationstest zeigt, wo das fehlt.
