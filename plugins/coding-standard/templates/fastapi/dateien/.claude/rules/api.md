---
paths: ['app/**']
---

# Schnittstelle (FastAPI)

- **Router bleiben dünn.** Parsen, autorisieren, an einen Service delegieren, Antwort-Schema
  zurückgeben. Sobald in einem Router eine Bedingung steht, die etwas fachlich entscheidet,
  gehört sie in den Service — dort ist sie ohne HTTP prüfbar.
- **Autorisierung als Abhängigkeit** (`Depends(...)`) am Router oder an der Route. Nie im
  Client, nie in einer Vorlage, nie „weil die Route ohnehin nur intern erreichbar ist".
- **`response_model` immer setzen.** Kein rohes Dict nach außen, kein ORM-Objekt
  serialisieren — sonst wandert früher oder später ein Feld mit, das niemand dort haben
  wollte.
- **Keine Secrets in Defaults.** `os.environ.get("X", "dev-secret")` ist verboten. Ein
  fehlendes Geheimnis bricht den Start ab, mit klarer Meldung.
- **Konfiguration nur in `app/settings.py`.** Ein `os.environ`-Aufruf in einem Fachmodul
  macht Konfiguration unauffindbar; er wird beim nächsten Anfassen der Datei aufgelöst.
- **Kein `shell=True`,** keine zusammengesetzten SQL-Strings, keine Pfadbildung aus
  Nutzereingaben ohne Normalisierung und Prüfung.
- **Keine personenbezogenen Daten und keine Tokens in Logs.** Logs gehen nach stdout,
  strukturiert; Docker rotiert.

## Weiteres

- Neue Fachmodule als `app/modules/<thema>/` mit `router.py`, `service.py`, `schemas.py`,
  bei Bedarf `repo.py`. Registriert wird der Router in `app/main.py`.
- `/healthz` bleibt ohne äußere Abhängigkeiten — der Compose-Healthcheck zeigt darauf. Eine
  Prüfung mit Datenbank gehört unter `/readyz`.
- Hintergrundarbeit zuerst über `BackgroundTasks`; bei Wachstum ein Worker-Prozess aus
  demselben Abbild — keine Threads im Request.
- Alle sichtbaren Texte und Fehlermeldungen Deutsch mit echten Umlauten; Bezeichner bleiben
  ASCII.
