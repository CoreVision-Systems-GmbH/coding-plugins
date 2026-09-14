| Zweck                        | Befehl                                             |
| ---------------------------- | -------------------------------------------------- |
| Umgebung aktivieren (Windows)| `source .venv/Scripts/activate`                    |
| Umgebung aktivieren (Linux)  | `source .venv/bin/activate`                        |
| Abhängigkeiten installieren  | `pip install -r requirements-dev.txt`              |
| Formatierung prüfen / setzen | `ruff format --check .` / `ruff format .`          |
| Linter                       | `ruff check .` (Korrektur: `ruff check --fix .`)   |
| Typen prüfen                 | `mypy app`                                         |
| Tests                        | `pytest`                                           |
| Sicherheitshinweise          | `pip-audit -r requirements.txt`                    |
| Alles prüfen                 | `ruff format --check . && ruff check . && mypy app && pytest` |
| Lokal starten                | `uvicorn app.main:app --reload --port 8080`        |

Der Dienst antwortet unter `/healthz` mit der ausgelieferten Fassung; die Schnittstelle
beschreibt sich selbst unter `/docs`.
