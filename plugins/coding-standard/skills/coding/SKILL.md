---
name: coding
description: Firmenstandard von Hand laden (Kern + Stack-Overlay) und die Startroutine fahren — für Sessions ohne automatische Aktivierung (Cowork, Repo ohne Plugin-Erklärung) oder um den Standard bewusst nachzuladen. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: [Aufgabe oder Kontext]
---

# /coding — Standard laden und starten

Aufgabe oder Kontext aus dem Aufruf: `$ARGUMENTS`

In Repos, die den Standard erklären (`coding-standard@corevision` in `.claude/settings.json`),
lädt ein SessionStart-Hook Kern und Overlay bereits automatisch — dieser Aufruf wiederholt
das dann nur und fährt zusätzlich die Startroutine.

1. Lies `${CLAUDE_PLUGIN_ROOT}/core/kern.md`. Er gilt ab jetzt für die gesamte Session.
2. Erkenne den Stack und lies das passende Overlay unter `${CLAUDE_PLUGIN_ROOT}/stacks/`:
   - `composer.json` mit `laravel/framework` → `laravel.md`
   - `requirements*.txt` oder `pyproject.toml` mit `fastapi` → `fastapi.md`
   - `package.json` mit `astro` → `astro.md`
   - `composer.json` mit `roots/wordpress` oder eine `wp-config.php` im Wurzelverzeichnis → `wordpress.md`
   - `package.json` mit `next` → `nextjs.md` (Ausnahme-Overlay, gilt für den Bestand)
   - `.coding-standard` mit `stack: <name>` → `<name>.md` (z. B. `script`)
   Mehrere Treffer → mehrere Overlays. Kein Treffer → sag es; dann gilt nur der Kern.
3. Startroutine: `CLAUDE.md`, `CHANGES.md` („Unveröffentlicht“), `docs/status.md`, die letzten
   zehn Commits, offene PRs und Issues zum Thema.
4. Bestätige in drei Zeilen: Standard aktiv (Kern + welches Overlay), erkannter Stack, was zur
   Aufgabe schon offen ist. Danach weiter nach Kern — bei `$ARGUMENTS` direkt mit „Denken vor Code“.
