| Zweck                                   | Befehl                                                        |
| --------------------------------------- | ------------------------------------------------------------- |
| Abhängigkeiten installieren             | `composer install`                                            |
| Coding-Standards prüfen / setzen        | `composer lint` / `composer lint:fix`                         |
| Statische Analyse (PHPStan Stufe 6)     | `composer analyse`                                            |
| Strukturprüfung (Theme, ENV-Schema)     | `composer test`                                               |
| Sicherheitshinweise                     | `composer audit`                                              |
| Alles prüfen                            | `composer check`                                              |
| Dev-Instanz (Dev-Server, mit MariaDB)   | `deploy/dev.sh up` (Protokoll: `deploy/dev.sh logs`)          |
| wp-cli in der Dev-Instanz               | `docker compose -p {{NAME}}-dev exec app wp <befehl>`         |

Die Prüfungen laufen ohne Datenbank. Die Site selbst gibt es nur im Verbund mit MariaDB —
entwickelt und getestet wird sie auf dem Dev-Server: `.env` aus `.env.example` ableiten
(`APP_DOMAIN`, `WP_HOME=https://dev.<APP_DOMAIN>`, Werte aus dem Tresor), dann
`deploy/dev.sh up`. Danach läuft die Site unter `https://dev.<APP_DOMAIN>` (nur im Tailnet);
die Erstinstallation der Dev-Site steht in `compose.dev.yaml`, auf dem Prod-Server macht sie
`deploy/install.sh`. Anmeldung unter `/wp/wp-login.php`.
