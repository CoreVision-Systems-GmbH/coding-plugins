# {{NAME}} — Produktionsabbild
#
# Ein schlankes Abbild, ein Prozess, kein Root. TLS und Hostnamen macht der
# Edge-Caddy des Servers; hier wird nur einfaches HTTP auf 8080 gesprochen.

FROM python:3.12-slim

# Der Kennsatz des Abbilds. Der Release-Workflow reicht den Git-Tag ohne
# führendes "v" herein; ohne Angabe bleibt es bei "dev". Der Dienst liest den
# Wert über settings.version und zeigt ihn unter /healthz.
ARG APP_IMAGE_VERSION=dev
ENV APP_IMAGE_VERSION=$APP_IMAGE_VERSION

LABEL org.opencontainers.image.version=$APP_IMAGE_VERSION \
      org.opencontainers.image.source=https://github.com/{{OWNER}}/{{NAME}}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Abhängigkeiten zuerst, damit die Ebene bei reinen Code-Änderungen hält.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Kein Root: Ein Dienst, der nur lesen und in DATA_DIR schreiben muss, braucht
# keine Rechte darüber hinaus.
RUN useradd --system --create-home --uid 10001 dienst \
    && mkdir -p /data \
    && chown -R dienst:dienst /app /data
USER dienst

ENV {{ENV_PREFIX}}DATA_DIR=/data

EXPOSE 8080

# --proxy-headers ist Pflicht hinter dem Edge-Caddy: Ohne die Angabe sieht
# Uvicorn weder die Client-Adresse noch das ursprüngliche Schema, und
# secure-Cookies gehen verloren.
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--proxy-headers", \
     "--forwarded-allow-ips", "*"]
