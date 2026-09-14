---
name: laravel
description: Stack-Overlay Laravel (Laravel 13, Filament 5, Inertia + React) von Hand laden — Zuständigkeiten, Grenzen, Werkzeugkette, Betriebsvertrag. Nur nötig, wenn der Standard nicht automatisch geladen wurde. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: [Aufgabe oder Kontext]
---

# /laravel — Stack-Overlay laden

Aufgabe oder Kontext aus dem Aufruf: `$ARGUMENTS`

1. Lies `${CLAUDE_PLUGIN_ROOT}/stacks/laravel.md`. Es ergänzt den Kern (`core/kern.md`) —
   ist der Kern in dieser Session noch nicht geladen, lies ihn zuerst.
2. Stelle den Ist-Stand fest: `composer.json`/`composer.lock` (Laravel-, Filament-, Inertia-Fassung),
   `package.json`, `CLAUDE.md`, `.ai/rules/` (Boost), `git status`.
3. Bestätige kurz: Overlay aktiv, erkannte Fassungen, und — wenn `$ARGUMENTS` eine Funktion
   beschreibt — den UI-Flächen-Entscheid nach Abschnitt 1 des Overlays oder die fehlende Angabe,
   die ihn verhindert.
