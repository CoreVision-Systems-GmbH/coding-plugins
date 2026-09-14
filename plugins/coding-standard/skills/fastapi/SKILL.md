---
name: fastapi
description: Stack-Overlay FastAPI (Python 3.12) von Hand laden — Zuständigkeiten, Grenzen, Werkzeugkette, Betriebsvertrag. Nur nötig, wenn der Standard nicht automatisch geladen wurde. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: [Aufgabe oder Kontext]
---

# /fastapi — Stack-Overlay laden

Aufgabe oder Kontext aus dem Aufruf: `$ARGUMENTS`

1. Lies `${CLAUDE_PLUGIN_ROOT}/stacks/fastapi.md`. Es ergänzt den Kern (`core/kern.md`) —
   ist der Kern in dieser Session noch nicht geladen, lies ihn zuerst.
2. Stelle den Ist-Stand fest: `requirements*.txt` oder `pyproject.toml` (FastAPI-, Pydantic-,
   Uvicorn-Fassung), vorhandene Werkzeuge (ruff, mypy, pytest), `CLAUDE.md`, `git status`.
3. Bestätige kurz: Overlay aktiv, erkannte Fassungen, und wo das Repo vom Overlay abweicht
   (z. B. verstreute `os.environ.get`, fehlendes `settings.py`) — als Hinweis, nicht als Auftrag.
