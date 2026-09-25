| Zweck                            | Befehl                                                        |
| -------------------------------- | ------------------------------------------------------------- |
| Alles prüfen (Typen, Bau, Tests) | `npm run check`                                               |
| Abhängigkeiten installieren      | `npm ci`                                                      |
| Entwicklung                      | `npm run dev`                                                 |
| Nur Typen und Vorlagen           | `npm run check:types`                                         |
| Bauen                            | `npm run build`                                               |
| Tests (gegen `dist/`)            | `npm test` (= `node --test "tests/**/*.test.mjs"`)            |
| Sicherheitshinweise              | `npm audit --omit=dev --audit-level=high`                     |
| Abbild lokal bauen               | `APP_VERSION=local docker compose -f compose.yaml -f compose.build.yaml build` |
| Dev-Instanz (Dev-Server)         | `deploy/dev.sh up` → `https://dev.<APP_DOMAIN>`               |

Die Tests prüfen das Ergebnis des Baus — `npm test` setzt `npm run build` voraus; `npm run
check` macht beides in der richtigen Reihenfolge, die CI führt dieselben Schritte aus. Die Site
hat keine Laufzeit-Konfiguration: `site` in `astro.config.mjs` und alle `PUBLIC_*`-Werte
stehen beim Bau fest; `/healthz` des Abbilds meldet die ausgelieferte Fassung.
