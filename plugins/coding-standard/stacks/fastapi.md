# Stack-Overlay FastAPI — Python 3.12

Ergänzt den Kern für FastAPI-Dienste (z. B. corevision-mak, corevision-mon). Hier stehen Firmenentscheidungen; Bibliotheks-Idiome kommen aus der offiziellen Dokumentation.

## 1. Zuständigkeiten & Architektur
- Paket `app/`: `main.py` (App-Aufbau, Router-Registrierung, `/healthz`), `settings.py` (die **eine** Stelle für Konfiguration), `auth.py` (Zugang), fachliche Module unter `app/modules/<thema>/` mit `router.py`, `service.py`, `schemas.py`, bei Bedarf `repo.py`.
- Router sind dünn: parsen, autorisieren, an einen Service delegieren, Antwort-Schema zurückgeben. Fachlogik liegt in Services und ist ohne HTTP testbar.
- Ein- und Ausgaben immer als Pydantic-Modelle (`response_model` setzen); keine rohen Dicts nach außen, keine ORM-Objekte serialisieren.
- Persistenz: SQLite für kleine interne Werkzeuge (Datei unter `DATA_DIR`), PostgreSQL für Produkte. Schemaänderungen als Migration (Alembic); „CREATE IF NOT EXISTS beim Start“ ist kein Dauerzustand.
- Hintergrundarbeit zuerst über `BackgroundTasks`; bei Wachstum ein Worker-Prozess aus demselben Image — keine Threads im Request.

## 2. Grenzen (nicht verhandelbar)
- Autorisierung als Abhängigkeit (`Depends(...)`) je Router oder Route — nie in Templates oder im Client.
- Keine Secrets in Defaults: `os.environ.get("X", "dev-secret")` ist verboten; ein fehlendes Secret bricht den Start mit klarer Meldung ab.
- Kein `shell=True`, keine zusammengesetzten SQL-Strings, keine Pfadbildung aus Nutzereingaben ohne Normalisierung und Prüfung.
- Keine personenbezogenen Daten oder Tokens in Logs.

## 3. Werkzeugkette
- Befehle aus dem Repo ermitteln (`README`, `Makefile`, `pyproject.toml`). Standard für neue Dienste: `ruff format` + `ruff check` (eine Konfiguration in `pyproject.toml`), `pytest` mit `TestClient`/`httpx.AsyncClient`, `pip-audit`; Typen mit `mypy --strict` für neue Module, Bestand schrittweise.
- Abhängigkeiten gepinnt (`==` in `requirements.txt` oder Lockdatei); Bumps als eigener PR (Dependabot `pip`).
- CI-Reihenfolge: `pip install -r requirements.txt -r requirements-dev.txt` → `ruff format --check` → `ruff check` → `mypy` → `pytest` → `pip-audit` → `docker build`.

## 4. Betriebsvertrag
1. **Runtime:** `python:3.12-slim`, Non-root-Benutzer, `uvicorn app.main:app --host 0.0.0.0 --port 8080 --proxy-headers --forwarded-allow-ips='*'`. Ein Image je Dienst. Der Edge-Caddy terminiert TLS, kein veröffentlichter Port, App im Netz `edge` plus eigenem internen Netz.
2. **Konfiguration:** ausschließlich über ENV, gelesen an einer Stelle (`settings.py`, pydantic-settings oder gleichwertig); `.env.example` als Schema mit Kommentar je Schlüssel; Präfix je Dienst (`MGMT_`, `MAK_`, `MON_`).
3. **Health:** `GET /healthz` → 200 ohne äußere Abhängigkeiten; optional `/readyz` mit Datenbankprüfung. Der Compose-Healthcheck zeigt darauf.
4. **Logs:** nach stdout, strukturiert (JSON oder Schlüssel=Wert), ohne PII; Docker rotiert.
5. **Version im Produkt:** Build-Arg `APP_IMAGE_VERSION` → `settings.version` → sichtbar in der `/healthz`-Antwort und im UI-Footer.
6. **Lieferung:** wie im Kern — `release.yml` → GHCR (`X.Y.Z`, `X.Y`, `sha-…`), Server ziehen per `deploy/update.sh <tag>` (Backup → Pull → Migration → Start → Health).
7. **Daten:** SQLite-Dateien und Uploads in einem Volume unter `DATA_DIR`; Backup = `sqlite3 .backup` oder Dateikopie im Ruhezustand; PostgreSQL per `pg_dump -Fc`.
8. **Qualitätsgates:** neue Router nur mit Tests für erlaubten **und** verweigerten Zugriff; Fehlerpfade (401/403/404/422) getestet; kein Merge mit offenen `ruff`-Befunden.

## 5. Fallen (stack-typisch)
- `os.environ.get` verstreut über Module macht Konfiguration unauffindbar — zentralisieren, sobald ein Modul angefasst wird.
- `TestClient` ohne `with` startet keine Lifespan-Ereignisse.
- Cookies hinter dem Proxy: `secure` nur, wenn `X-Forwarded-Proto` ausgewertet wird (`--proxy-headers`).
- Uvicorn ohne `--proxy-headers` sieht weder Client-IP noch Schema des Caddy.
- Zeit: `datetime.now(timezone.utc)` speichern, lokal nur anzeigen; naive Datetimes verbieten.
