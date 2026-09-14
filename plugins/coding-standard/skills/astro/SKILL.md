---
name: astro
description: Stack-Overlay Astro (Astro 7, statische Website) von Hand laden — Zuständigkeiten, Grenzen, Werkzeugkette, Betriebsvertrag. Nur nötig, wenn der Standard nicht automatisch geladen wurde. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: [Aufgabe oder Kontext]
---

# /astro — Stack-Overlay laden

Aufgabe oder Kontext aus dem Aufruf: `$ARGUMENTS`

1. Lies `${CLAUDE_PLUGIN_ROOT}/stacks/astro.md`. Es ergänzt den Kern (`core/kern.md`) —
   ist der Kern in dieser Session noch nicht geladen, lies ihn zuerst.
2. Stelle den Ist-Stand fest: `package.json` (Astro-, Sitemap-, Check-Fassung, Scripts),
   `astro.config.mjs` (`site`, `output`, `trailingSlash`, Integrationen), ob es ein
   Basis-Layout und Content Collections gibt, `CLAUDE.md`, `git status`.
3. Bestätige kurz: Overlay aktiv, erkannte Fassungen, und wo das Repo vom Overlay abweicht
   (z. B. `site` noch auf der Platzhalter-Domain, Inseln ohne Begründung, Bilder in
   `public/` statt `astro:assets`) — als Hinweis, nicht als Auftrag.
