import { expect, test } from '@playwright/test';

// Klick-Sweep: von der Startseite jedem internen Link folgen (eine Ebene,
// höchstens 60 Seiten) und prüfen, dass keine Seite 4xx/5xx liefert,
// Konsolenfehler wirft oder Anfragen verliert. Findet die Seite, die niemand
// mehr angeklickt hätte — den Tippfehler im href, das gelöschte Bild, den
// toten Anker.

const HOECHSTENS = 60;
const DATEIEN = /\.(pdf|zip|xml|txt|ics|csv|docx?|xlsx?|pptx?)$/i;

test('alle internen Links der Startseite antworten sauber', async ({
    page,
    baseURL,
}) => {
    test.setTimeout(HOECHSTENS * 10_000);
    const ursprung = new URL(baseURL ?? 'http://127.0.0.1:8080').origin;
    const befunde: string[] = [];

    await page.goto('/', { waitUntil: 'load' });
    const hrefs = await page
        .locator('a[href]')
        .evaluateAll((as) => as.map((a) => (a as HTMLAnchorElement).href));
    const ziele = [
        ...new Set(
            hrefs
                .filter((h) => h.startsWith(ursprung))
                .map((h) => new URL(h))
                .filter((u) => u.pathname !== '/')
                .map((u) => u.pathname + u.search)
                .filter((p) => !DATEIEN.test(p)),
        ),
    ].slice(0, HOECHSTENS);

    expect(
        ziele.length,
        'die Startseite verlinkt nichts Internes — Sweep ohne Ziele',
    ).toBeGreaterThan(0);

    for (const ziel of ziele) {
        const konsole: string[] = [];
        const gescheitert: string[] = [];
        const anKonsole = (m: { type(): string; text(): string }) => {
            if (m.type() === 'error') konsole.push(m.text());
        };
        const anFehler = (q: { url(): string }) => gescheitert.push(q.url());
        page.on('console', anKonsole);
        page.on('requestfailed', anFehler);

        try {
            const antwort = await page.goto(ziel, { waitUntil: 'load' });
            const status = antwort?.status() ?? 0;
            if (status >= 400 || status === 0) {
                befunde.push(`${ziel}: Status ${status}`);
            }
            if (konsole.length) {
                befunde.push(`${ziel}: Konsole — ${konsole.join(' | ')}`);
            }
            if (gescheitert.length) {
                const liste = gescheitert.join(', ');
                befunde.push(`${ziel}: gescheitert — ${liste}`);
            }
        } catch (fehler) {
            befunde.push(`${ziel}: ${String(fehler)}`);
        } finally {
            page.off('console', anKonsole);
            page.off('requestfailed', anFehler);
        }
    }

    expect(
        befunde,
        `${befunde.length} von ${ziele.length} Seiten mit Befund`,
    ).toEqual([]);
});
