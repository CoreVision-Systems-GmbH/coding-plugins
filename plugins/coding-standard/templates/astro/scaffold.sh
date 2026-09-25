#!/usr/bin/env bash
# Gerüst für den Stack astro.
#
# Wird von scripts/projekt-neu.sh zweimal aufgerufen:
#   PHASE=geruest     — Zielordner ist leer oder fehlt; hier wird nur angelegt.
#   PHASE=einrichten  — die Vorlagen liegen bereits im Zielordner.
#
# Es gibt keinen Installer: `npm create astro` fragt interaktiv nach und ändert
# von Fassung zu Fassung, was es anlegt. Das Gerüst kommt deshalb vollständig
# aus templates/astro/dateien. Diese Phase installiert die Abhängigkeiten
# (erzeugt package-lock.json) und lässt einmal alle Prüfungen laufen — ein
# Gerüst, das nicht grün ist, wird gar nicht erst ausgeliefert.
#
# Umgebung: NAME DIR OWNER IMAGE PURPOSE ENV_PREFIX PHASE

set -euo pipefail

meldung() { printf '   %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

if [ "$PHASE" = "geruest" ]; then
    mkdir -p "$DIR"
    exit 0
fi

cd "$DIR"

# Unter Windows liegt neben npm.cmd ein Shell-Shim `npm`, den Git Bash über
# command -v findet — ein eigener .cmd-Umweg ist nicht nötig.
command -v node >/dev/null 2>&1 || abbruch "node ist nicht im PATH."
command -v npm  >/dev/null 2>&1 || abbruch "npm ist nicht im PATH."

# Major und Minor prüfen: Astro 7 verlangt >= 22.12 (npm view astro engines).
node -e 'const [a, b] = process.versions.node.split(".").map(Number); process.exit(a > 22 || (a === 22 && b >= 12) ? 0 : 1)' \
    || abbruch "Astro 7 braucht Node 22.12 oder neuer; gefunden: $(node --version)."

# Astro meldet Nutzung an den Hersteller, solange das nicht abgeschaltet ist.
export ASTRO_TELEMETRY_DISABLED=1

meldung "Abhängigkeiten installieren (npm install — erzeugt package-lock.json)"
npm install --no-audit --no-fund

meldung "npm run check (Typen, Bau, Tests)"
npm run check

# Die Platzhalter-Domain aus der Vorlage bleibt bewusst stehen: Welche Domain
# die Site bekommt, weiß das Skript nicht. Ohne die echte zeigen Canonicals,
# Sitemap und robots.txt ins Leere.
printf '%s\n' \
    '`site` in astro.config.mjs auf die echte Domain setzen (Canonical, Sitemap) — dieselbe Adresse in public/robots.txt.' \
    'Impressum und Datenschutzerklärung befüllen (src/pages/impressum.astro, datenschutz.astro) — der Rauchtest verlangt UID und Verantwortlichen; bis dahin bleibt er rot.' \
    >> "$DIR/.projekt-neu-nacharbeit"

meldung "Gerüst steht und ist grün."
