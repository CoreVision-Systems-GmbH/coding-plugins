---
paths: ['src/**']
---

# Seiten und Inhalte (Astro, statisch)

- **Kein Client-JavaScript ohne Grund.** Eine Insel (`client:*`) bekommt im Kommentar daneben
  die Begründung, warum HTML und CSS nicht reichen. Server Islands nur bei echtem Bedarf an
  Laufzeitdaten — dann ist zu fragen, ob die Site noch statisch ist.
- **Jede Seite läuft über `src/layouts/Base.astro`** und gibt `title` und `description` mit.
  Canonical und `lang="de"` kommen aus dem Layout; eine Seite ohne Layout gibt es nicht.
- **Bilder über `astro:assets`** (`<Image>`/`<Picture>` aus `src/assets/`). In `public/` liegt
  nur, was unverändert durchgereicht wird (Favicon, `robots.txt`, Downloads).
- **Content Collections mit Schema** (`src/content.config.ts`), sobald es mehr als eine Handvoll
  gleichartiger Seiten gibt. Ein Eintrag, der das Schema verletzt, bricht den Bau ab — gewollt.
- **Keine Anmeldung, keine personenbezogenen Daten, keine Formulare mit Serverlogik.** Braucht
  ein Vorhaben davon etwas, ist es keine Content-Site — dafür gilt der Stack `laravel`.
- **Keine Geheimnisse im Bau.** Was in `PUBLIC_*` oder im Quelltext steht, landet im HTML.
- **Keine fremden Skripte ohne Entscheidung** (Tracking, Schriften von Drittservern,
  Einbettungen) — jedes ist ein Datenschutz-Thema, kein Handgriff.

## Weiteres

- `site` in `astro.config.mjs` ist Bauzeit: Canonicals, Sitemap und `robots.txt` hängen daran.
  Zeigt sie noch auf `<name>.invalid`, ist die Site nicht fertig.
- `trailingSlash: 'always'` bleibt: Der Caddy im Abbild leitet `/seite` auf `/seite/` um, und
  der Dev-Server soll dasselbe tun. Interne Links deshalb immer mit Schrägstrich am Ende.
- Astro 7 entfernt Leerraum nach JSX-Regeln — Inline-Elemente nicht auf Leerraum zwischen Tags
  verlassen. Der Compiler weist ungeschlossene Tags ab.
- Alle sichtbaren Texte Deutsch mit echten Umlauten; Bezeichner, Dateinamen und Pfade ASCII.
