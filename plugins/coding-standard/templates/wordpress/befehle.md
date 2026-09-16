| Zweck                                   | Befehl                                                        |
| --------------------------------------- | ------------------------------------------------------------- |
| Abhängigkeiten installieren             | `composer install`                                            |
| Coding-Standards prüfen / setzen        | `composer lint` / `composer lint:fix`                         |
| Statische Analyse (PHPStan Stufe 6)     | `composer analyse`                                            |
| Strukturprüfung (Theme, ENV-Schema)     | `composer test`                                               |
| Sicherheitshinweise                     | `composer audit`                                              |
| Alles prüfen                            | `composer check`                                              |
| Site lokal (mit MariaDB)                | `APP_VERSION=local docker compose -f compose.yaml -f compose.build.yaml -f compose.dev.yaml up --build` |
| Abbild lokal bauen                      | `APP_VERSION=local docker compose -f compose.yaml -f compose.build.yaml build` |
| wp-cli im Verbund                       | `docker compose exec app wp <befehl>`                         |

Die Prüfungen laufen ohne Datenbank. Die Site selbst gibt es nur im Docker-Verbund — ohne
MariaDB startet WordPress nicht: einmalig `docker network create edge`, `.env` aus
`.env.example` ableiten (lokal genügen Platzhalter-Werte), dann `up --build`. Danach läuft
die Site unter `http://localhost:8080`; die Erstinstallation macht lokal
`docker compose exec app wp core install --url=http://localhost:8080 --title=Lokal --admin_user=<name> --admin_email=<mail> --prompt=admin_password`
(auf dem Server `deploy/install.sh`). Anmeldung unter `/wp/wp-login.php`.
