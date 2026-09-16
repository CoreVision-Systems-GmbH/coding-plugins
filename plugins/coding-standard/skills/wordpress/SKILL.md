---
name: wordpress
description: Stack-Overlay WordPress (WordPress 7, Bedrock-Layout, MariaDB) von Hand laden — Zuständigkeiten, Grenzen, Werkzeugkette, Betriebsvertrag. Nur nötig, wenn der Standard nicht automatisch geladen wurde. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: [Aufgabe oder Kontext]
---

# /wordpress — Stack-Overlay laden

Aufgabe oder Kontext aus dem Aufruf: `$ARGUMENTS`

1. Lies `${CLAUDE_PLUGIN_ROOT}/stacks/wordpress.md`. Es ergänzt den Kern (`core/kern.md`) —
   ist der Kern in dieser Session noch nicht geladen, lies ihn zuerst.
2. Stelle den Ist-Stand fest: `composer.json`/`composer.lock` (WordPress-Fassung, Plugins),
   `config/application.php` (`DISALLOW_FILE_MODS`, `DISABLE_WP_CRON`, `WP_DEFAULT_THEME`),
   `web/app/mu-plugins/` und `web/app/themes/`, `CLAUDE.md`, `docs/decisions/` (ADR je
   Plugin), `git status`.
3. Bestätige kurz: Overlay aktiv, erkannte Fassungen, und wo das Repo vom Overlay abweicht
   (z. B. Plugins ohne ADR oder ohne Composer-Quelle, Verhalten in der `functions.php`,
   `WP_HOME` noch auf der Platzhalter-Domain, ein Bestand ohne Bedrock-Layout) — als
   Hinweis, nicht als Auftrag. Bei einem Bestand ohne Bedrock-Layout gilt das Overlay
   sinngemäß: Grenzen und Betriebsvertrag zuerst, das Layout wandert nicht nebenbei.
