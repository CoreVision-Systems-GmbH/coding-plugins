import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

// Barrierefreiheit mit axe-core (WCAG 2.1, Stufen A und AA) — ein Schalter je
// Projekt, standardmäßig aus. Einschalten, wenn das Produkt unter das
// Barrierefreiheitsgesetz (BaFG) fällt oder der Kunde es verlangt:
// EINGESCHALTET auf true setzen und im PR begründen. axe findet einen Teil der
// Barrieren (Kontraste, fehlende Beschriftungen und Alternativtexte, falsche
// Rollen); Tastaturbedienung und Screenreader prüft weiterhin ein Mensch.
const EINGESCHALTET = false;

// Geprüft werden die Seiten aus deploy/smoke.txt, die 200 liefern — dieselbe
// Liste wie der Rauchtest. Eine Seite gehört dorthin, nicht in eine zweite Liste.
// Die Zustandsberichte (/up, /healthz) sind keine Seiten für Menschen.
const ZUSTAND = new Set(['/up', '/healthz']);

function seiten(): string[] {
    const datei = fileURLToPath(
        new URL('../../deploy/smoke.txt', import.meta.url),
    );
    return readFileSync(datei, 'utf8')
        .split(/\r?\n/)
        .map((z) => z.replace(/(^|\s)#.*$/, '').trim())
        .filter((z) => z.length > 0)
        .map((z) => z.split(/\s+/))
        .filter(([, status = '200']) => status === '200')
        .map(([pfad]) => pfad)
        .filter((pfad) => !ZUSTAND.has(pfad));
}

test.describe('Barrierefreiheit (axe-core, WCAG 2.1 AA)', () => {
    test.skip(!EINGESCHALTET, 'aus — Schalter EINGESCHALTET in dieser Datei');

    for (const pfad of seiten()) {
        test(`${pfad} ohne Verstöße`, async ({ page }) => {
            const antwort = await page.goto(pfad, { waitUntil: 'load' });
            const art = antwort?.headers()['content-type'] ?? '';
            test.skip(!art.includes('text/html'), `${pfad} ist keine HTML-Seite`);
            // Inertia rendert erst im Browser: Ohne Warten prüfte axe ein leeres
            // #app und meldete falsch grün.
            await page.waitForLoadState('networkidle');

            const ergebnis = await new AxeBuilder({ page })
                .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
                .analyze();
            const verstoesse = ergebnis.violations.map(
                (v) =>
                    `${v.id} (${v.impact ?? 'ohne Stufe'}): ${v.help} — ${v.nodes.length}×`,
            );
            expect(verstoesse, `${verstoesse.length} Verstöße`).toEqual([]);
        });
    }
});
