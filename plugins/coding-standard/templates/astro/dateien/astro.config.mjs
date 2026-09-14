// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// Die öffentliche Adresse der Site. Bauzeit, nicht Laufzeit: Canonical-Links
// und die Sitemap werden daraus erzeugt und stehen fest im Abbild — eine Site
// je Abbild. Die Platzhalter-Domain vor dem ersten Release durch die echte
// ersetzen (steht in der Nacharbeit); dieselbe Adresse gehört in
// public/robots.txt.
const site = 'https://{{NAME}}.invalid';

export default defineConfig({
    site,

    // Nur HTML-Dateien. Alles, was einen Server bräuchte, ist keine
    // Content-Site — dafür gilt der Stack laravel.
    output: 'static',

    // Der Caddy im Abbild leitet /seite auf /seite/ um (kanonische
    // Verzeichnis-Adressen). Damit der Dev-Server dasselbe tut und keine Links
    // entstehen, die nur lokal funktionieren, verlangt auch er den Schrägstrich.
    trailingSlash: 'always',

    integrations: [sitemap()],
});
