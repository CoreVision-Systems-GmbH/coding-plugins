# {{NAME}} — Produktionsabbild
#
# FrankenPHP im klassischen Modus. Der Bau holt WordPress und die Plugins per Composer
# und legt die deutschen Sprachpakete dazu; im Laufzeit-Abbild gibt es weder Composer
# noch Quelltext-Werkzeuge. Der Container läuft als www-data — WordPress verarbeitet
# Uploads von Fremden, das ist kein Prozess für Root.

# ---------------------------------------------------------------- Bau-Stufe
FROM dunglas/frankenphp:1-php8.4 AS builder

RUN install-php-extensions mysqli gd intl zip exif opcache

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Abhängigkeiten zuerst, damit die Ebene bei reinen Code-Änderungen hält. Hier
# entstehen web/wp (WordPress) und web/app/plugins (Composer-Plugins).
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --prefer-dist --no-interaction --no-progress

COPY . .

# Sprachpakete zur gebauten Fassung — zur Laufzeit lädt WordPress keine
# (DISALLOW_FILE_MODS). Fehlt eines für ein Plugin, meldet das Skript es und der Bau
# läuft weiter; fehlt das des Kerns, bricht der Bau ab.
RUN php docker/sprachpakete.php de_DE

RUN composer dump-autoload --optimize --no-dev

# ------------------------------------------------------------- Laufzeit-Stufe
FROM dunglas/frankenphp:1-php8.4

# Der Kennsatz des Abbilds. Der Release-Workflow reicht den Git-Tag ohne führendes "v"
# herein; ohne Angabe bleibt es bei "dev". Das Mu-Plugin firmenstandard liest ihn und
# zeigt ihn unter /healthz, im HTML und in der Admin-Fußzeile.
ARG APP_IMAGE_VERSION=dev
ENV APP_IMAGE_VERSION=$APP_IMAGE_VERSION

# wp-cli für Erstinstallation, Datenbank-Update und den Dienst `cron`. Gepinnt wie
# jedes fremde Artefakt; der Bump ist ein Handgriff, Dependabot kennt phar-Downloads nicht.
ARG WP_CLI_VERSION=2.12.0

LABEL org.opencontainers.image.version=$APP_IMAGE_VERSION \
      org.opencontainers.image.source=https://github.com/{{OWNER}}/{{NAME}}

RUN install-php-extensions mysqli gd intl zip exif opcache \
    && curl -fsSL "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
        -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

COPY docker/php.ini /usr/local/etc/php/conf.d/app.ini
COPY docker/Caddyfile /etc/frankenphp/Caddyfile
COPY docker/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

WORKDIR /app
COPY --from=builder --chown=www-data:www-data /app /app

# Uploads sind das Einzige, was WordPress schreibt (Volume in compose.yaml). Caddy
# braucht /data und /config für seinen Zustand.
RUN mkdir -p web/app/uploads \
    && chown -R www-data:www-data web/app/uploads /data /config

ENV SERVER_NAME=:8080 \
    WP_CLI_CACHE_DIR=/tmp/wp-cli-cache

USER www-data

EXPOSE 8080
ENTRYPOINT ["entrypoint"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]
