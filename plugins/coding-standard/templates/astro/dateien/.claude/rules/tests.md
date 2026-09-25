---
paths: ['tests/**']
---

# Tests

- **Der Bau ist die erste Prüfung.** `npm run check` (Typen, Bau, Tests gegen `dist/`) läuft
  vor jedem Commit; was der Bau nicht meldet, prüfen `tests/*.test.mjs` am Ergebnis
  (`index.html`, `404.html`, Sitemap, Canonical, `lang="de"`).
- **Keine Tests ohne Aussage.** Kein Test, der nur bestätigt, dass Astro funktioniert; jeder
  Fix bringt einen Test mit, der ohne die Korrektur rot wäre.

## Browser (tests/e2e, Playwright)

- **Gegen die Dev-Instanz, aus dem Tailnet:** `E2E_BASE_URL=https://dev.<APP_DOMAIN> npm run e2e`
  (einmalig `npx playwright install chromium`). Nicht aus der GitHub-CI — `dev.*` ist dort
  nicht erreichbar.
- **Dieselbe Liste wie der Rauchtest:** `smoke.spec.ts` liest `deploy/smoke.txt` (Pfad, Status,
  Zeitbudget, Pflichtinhalt) und prüft dazu, was nur ein Browser sieht — Konsolenfehler,
  gescheiterte Anfragen (Bilder, Schriften, Skripte). Eine Route gehört in `smoke.txt`, nicht
  in einen zweiten Test.
- **Drei Viewports** (Desktop 1440, Tablet, Handy — alle mit Chromium, ein Browser genügt): Layoutfehler zeigen sich zuerst auf dem
  Handy. Ein Test läuft in allen drei Projekten.
- **Klick-Sweep** (`sweep.spec.ts`): jedem internen Link der Startseite folgen — kein 4xx/5xx,
  keine Konsolenfehler. Findet die Seite, die niemand mehr angeklickt hätte.
- **`retries: 0`.** Ein Test, der beim zweiten Mal grün wird, ist rot (flaky) und wird
  repariert, nicht wiederholt. Nachts auf dem Dev-Server `E2E_REPEAT=2`: jeder Test zweimal,
  ein Unterschied zwischen den Läufen ist der Befund. Ergebnis als `tests/e2e/ergebnis.json`.
  Die Spezifikationen werden mit `tsc -p tests/e2e` typgeprüft (Teil von `npm run check:types`).
