# Edge-Caddy des Firmenstandards: das offizielle Caddy-Abbild plus die DNS-Module für
# ACME DNS-01. Das offizielle Abbild beherrscht DNS-01 nicht — ohne diese Module bekäme
# ein Server, der nicht aus dem Internet erreichbar ist, kein Zertifikat.
#
# Alle Fassungen sind gepinnt: Derselbe Stand baut auf jedem Server dasselbe Abbild.
# Anheben: Fassung hier ändern, Test und CI (edge-image.yml) laufen lassen, Release.
ARG CADDY_VERSION=2.11.4

FROM caddy:${CADDY_VERSION}-builder AS builder
RUN xcaddy build \
    --with github.com/caddy-dns/hetzner/v2@v2.0.1 \
    --with github.com/caddy-dns/cloudflare@v0.2.4 \
    --with github.com/caddy-dns/acmedns@v0.7.0

FROM caddy:${CADDY_VERSION}
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
