| Zweck                             | Befehl                                             |
| --------------------------------- | -------------------------------------------------- |
| Alles prüfen (ruff, mypy, pytest) | `bash scripts/check.sh`                            |
| Umgebung aktivieren (Windows)     | `source .venv/Scripts/activate`                    |
| Umgebung aktivieren (Linux)       | `source .venv/bin/activate`                        |
| Abhängigkeiten installieren       | `pip install -r requirements-dev.txt`              |
| Formatierung prüfen / setzen      | `ruff format --check .` / `ruff format .`          |
| Linter                            | `ruff check .` (Korrektur: `ruff check --fix .`)   |
| Typen prüfen                      | `mypy app`                                         |
| Tests                             | `pytest`                                           |
| Sicherheitshinweise               | `pip-audit -r requirements.txt`                    |
| Lokal starten                     | `uvicorn app.main:app --reload --port 8080`        |
| Dev-Instanz (Dev-Server)          | `deploy/dev.sh up` → `https://dev.<APP_DOMAIN>`    |

`scripts/check.sh` nimmt das Python aus `.venv`, die Umgebung muss dafür nicht aktiviert sein;
die CI führt denselben Befehl aus. „Lokal starten“ braucht eine `.env` aus `.env.example` mit
gesetztem `DB_PASSWORD` — ohne sie bricht der Start ab; für `/healthz` muss die Datenbank nicht
laufen. Die Tests brauchen keine `.env`, sie verdrahten ihre Werte selbst. Der Dienst antwortet unter `/healthz` mit der
ausgelieferten Fassung; die Schnittstelle beschreibt sich selbst unter `/docs`.
