// Prüft das Ergebnis des Baus, nicht den Bau selbst: `npm run build` läuft
// vorher (scaffold, CI, Dockerfile). Was hier rot ist, wäre im Betrieb eine
// Seite ohne Sprache, ohne Titel oder ohne Fehlerseite.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = join(dirname(fileURLToPath(import.meta.url)), '..', 'dist');
const hinweis = 'dist/ fehlt oder ist unvollständig — vorher `npm run build` ausführen.';

function gebaut(datei) {
    const pfad = join(dist, datei);
    assert.ok(existsSync(pfad), `${datei}: ${hinweis}`);
    return readFileSync(pfad, 'utf8');
}

test('Startseite ist gebaut und trägt Sprache und Titel', () => {
    const html = gebaut('index.html');
    assert.match(html, /<html[^>]*\blang="de"/, 'lang="de" fehlt am <html>-Element');
    assert.match(html, /<title>[^<]+<\/title>/, '<title> fehlt oder ist leer');
    assert.match(html, /<meta name="description" content="[^"]+"/, 'Beschreibung fehlt');
    assert.match(html, /<link rel="canonical" href="https:\/\//, 'Canonical fehlt');
});

test('Fehlerseite 404.html ist gebaut', () => {
    gebaut('404.html');
});

test('Sitemap ist gebaut (setzt `site` voraus)', () => {
    gebaut('sitemap-index.xml');
});
