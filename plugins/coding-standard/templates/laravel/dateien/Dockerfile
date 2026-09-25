# {{NAME}} — Produktionsabbild
#
# FrankenPHP im klassischen Modus, ohne Octane: Der Anwendungsserver bringt bei
# den Lastprofilen, um die es hier geht, keinen messbaren Gewinn, handelt sich
# aber die gesamte Klasse von Zustandsfehlern zwischen Anfragen ein.
#
# Der Bau läuft in einer Stufe, die PHP und Node zugleich hat. Grund: Laravel
# Wayfinder erzeugt die TypeScript-Routen während des Vite-Baus per Artisan —
# ein reiner Node-Container könnte den Schritt nicht ausführen.

# ---------------------------------------------------------------- Bau-Stufe
FROM dunglas/frankenphp:1-php8.4 AS builder

RUN install-php-extensions \
        pdo_pgsql pgsql intl zip gd bcmath opcache pcntl exif

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Abhängigkeiten zuerst, damit die Ebenen bei reinen Code-Änderungen halten.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund

COPY . .

# Der Anwendungsname wird zur Bauzeit in die Assets eingebettet; die .env ist
# hier bewusst nicht verfügbar. Er gehört ohnehin zum Produkt, nicht zur
# Umgebung.
ENV VITE_APP_NAME="{{NAME}}"

RUN composer dump-autoload --optimize --no-dev --classmap-authoritative \
    && composer run-script post-autoload-dump \
    && npm run build \
    && rm -rf node_modules

# ------------------------------------------------------------- Laufzeit-Stufe
FROM dunglas/frankenphp:1-php8.4

# Der Kennsatz des Abbilds. Der Release-Workflow reicht den Git-Tag ohne
# führendes "v" herein; ohne Angabe bleibt es bei "dev". Die Anwendung liest
# den Wert über config('app.version') und zeigt ihn im Fußbereich.
ARG APP_IMAGE_VERSION=dev
ENV APP_IMAGE_VERSION=$APP_IMAGE_VERSION

LABEL org.opencontainers.image.version=$APP_IMAGE_VERSION \
      org.opencontainers.image.source=https://github.com/{{OWNER}}/{{NAME}}

RUN install-php-extensions \
        pdo_pgsql pgsql intl zip gd bcmath opcache pcntl exif

COPY docker/php.ini /usr/local/etc/php/conf.d/app.ini
COPY docker/Caddyfile /etc/frankenphp/Caddyfile
COPY docker/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

WORKDIR /app
COPY --from=builder --chown=www-data:www-data /app /app

# Die Verknüpfung public/storage entsteht beim Bau: Zur Laufzeit ist das
# Wurzeldateisystem schreibgeschützt (compose.yaml), der Entrypoint könnte
# sie nicht mehr anlegen.
RUN mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache \
    && php artisan storage:link

ENV SERVER_NAME=:8080

EXPOSE 8080
ENTRYPOINT ["entrypoint"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]
