# {{NAME}} — Produktionsabbild
#
# Zwei Stufen: Node baut das HTML, Caddy liefert es aus. Im Laufzeit-Abbild
# gibt es kein Node, keinen Quelltext und keine Abhängigkeiten — nur dist/
# und eine Caddyfile. TLS und Hostnamen macht der Edge-Caddy des Servers; hier
# wird nur einfaches HTTP auf 8080 gesprochen.

# ---------------------------------------------------------------- Bau-Stufe
FROM node:24-alpine AS builder

# Astro meldet Nutzung an den Hersteller, solange das nicht abgeschaltet ist.
ENV ASTRO_TELEMETRY_DISABLED=1

WORKDIR /build

# Abhängigkeiten zuerst, damit die Ebene bei reinen Inhaltsänderungen hält.
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .

# Der Kennsatz des Abbilds. Der Release-Workflow reicht den Git-Tag ohne
# führendes "v" herein; ohne Angabe bleibt es bei "dev". Beim Bau wandert er
# als PUBLIC_APP_VERSION ins HTML (Meta-Tag und Fußzeile des Layouts).
ARG APP_IMAGE_VERSION=dev
ENV PUBLIC_APP_VERSION=$APP_IMAGE_VERSION

RUN npm run build

# ------------------------------------------------------------- Laufzeit-Stufe
FROM caddy:2-alpine

# Derselbe Kennsatz noch einmal für die Laufzeit: Die Caddyfile setzt ihn in
# die Antwort unter /healthz ein.
ARG APP_IMAGE_VERSION=dev
ENV APP_IMAGE_VERSION=$APP_IMAGE_VERSION

LABEL org.opencontainers.image.version=$APP_IMAGE_VERSION \
      org.opencontainers.image.source=https://github.com/{{OWNER}}/{{NAME}}

COPY docker/Caddyfile /etc/caddy/Caddyfile
COPY --from=builder /build/dist /srv

# Eine kaputte Caddyfile soll beim Bau auffallen, nicht erst beim Start auf
# dem Server.
RUN caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# Kein Root: Der Webserver liest nur /srv und schreibt in seine eigenen
# Verzeichnisse (/config, /data). Port 8080 braucht keine Rechte.
RUN adduser -D -u 10001 web \
    && chown -R web:web /srv /config /data
USER web

EXPOSE 8080
