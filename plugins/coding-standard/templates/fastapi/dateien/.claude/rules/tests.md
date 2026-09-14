---
paths: ['tests/**']
---

# Tests

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
