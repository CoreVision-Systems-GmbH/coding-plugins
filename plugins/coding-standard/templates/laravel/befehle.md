| Zweck                                         | Befehl                                           |
| --------------------------------------------- | ------------------------------------------------ |
| Alles prüfen (Pint, Larastan, Pest, Frontend) | `composer check`                                 |
| Nur Backend (Pint, Larastan, Pest)            | `composer test`                                  |
| Nur Tests                                     | `php artisan test`                               |
| Formatierung prüfen / setzen                  | `composer lint:check` / `composer lint`          |
| Statische Analyse (Larastan Stufe 8)          | `composer types:check`                           |
| Frontend prüfen (Format + Lint)               | `npm run check` (Korrektur: `npm run check:fix`) |
| TypeScript prüfen                             | `npm run types:check`                            |
| Frontend bauen                                | `npm run build`                                  |
| Entwicklung                                   | `composer dev`                                   |
| CI-Äquivalent                                 | `composer ci:setup && composer ci:check`         |
| Dev-Instanz (Dev-Server)                      | `deploy/dev.sh up` → `https://dev.<APP_DOMAIN>`   |

**Nie `composer setup` aufrufen** — der Befehl enthält `php artisan migrate --force` und
schreibt in die Datenbank. Für die Einrichtung ohne Wanderung: `composer ci:setup`.

**PHP braucht `intl`.** Filament verlangt die Erweiterung; ohne sie enden Filament-Tests mit
HTTP 500. Unter Windows liegt die passende Fassung in `~/.config/herd/bin/php84/php.exe` —
die herd-lite-Fassung im PATH hat kein `intl`.
