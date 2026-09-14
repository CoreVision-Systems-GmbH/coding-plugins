| Zweck                        | Befehl                                                        |
| ---------------------------- | ------------------------------------------------------------- |
| Abhängigkeiten installieren  | `npm ci`                                                      |
| Entwicklung                  | `npm run dev`                                                 |
| Prüfen (Typen und Vorlagen)  | `npm run check`                                               |
| Bauen                        | `npm run build`                                               |
| Tests (gegen `dist/`)        | `npm test` (= `node --test "tests/**/*.test.mjs"`)            |
| Sicherheitshinweise          | `npm audit --omit=dev --audit-level=high`                     |
| Alles prüfen                 | `npm run check && npm run build && npm test`                  |
| Abbild lokal bauen           | `APP_VERSION=local docker compose -f compose.yaml -f compose.build.yaml build` |

Die Tests prüfen das Ergebnis des Baus — `npm test` setzt `npm run build` voraus. Die Site
hat keine Laufzeit-Konfiguration: `site` in `astro.config.mjs` und alle `PUBLIC_*`-Werte
stehen beim Bau fest; `/healthz` des Abbilds meldet die ausgelieferte Fassung.
