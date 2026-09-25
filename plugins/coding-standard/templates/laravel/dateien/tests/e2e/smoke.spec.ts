import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, test } from '@playwright/test';

// Rauchtest im Browser — dieselbe Liste wie deploy/smoke.sh (deploy/smoke.txt):
// Pfad, Status, Zeitbudget in Sekunden, Pflichtinhalt. Dazu, was nur ein
// Browser sieht: keine Fehler in der Konsole, keine gescheiterten Anfragen
// (Bilder, Schriften, Skripte), auf jedem Viewport.
//
// Gemessen wird wie bei curl die Antwortzeit des Hauptdokuments, nicht das
// Laden aller Unterressourcen über das Tailnet — das Budget in smoke.txt ist
// dafür gedacht. Ein erwarteter 3xx wird an der ersten Antwort der
// Weiterleitungskette geprüft; page.goto liefert sonst nur die letzte.

type Route = {
    pfad: string;
    status: number;
    budget: number;
    inhalt: string;
};

function routen(): Route[] {
    const datei = fileURLToPath(
        new URL('../../deploy/smoke.txt', import.meta.url),
    );
    return readFileSync(datei, 'utf8')
        .split(/\r?\n/)
        .map((z) => z.replace(/(^|\s)#.*$/, '').trim())
        .filter((z) => z.length > 0)
        .map((z) => {
            const [pfad, status = '200', budget = '3', ...rest] =
                z.split(/\s+/);
            return {
                pfad,
                status: Number(status),
                budget: Number(budget),
                inhalt: rest.join(' '),
            };
        });
}

for (const r of routen()) {
    const titel =
        `${r.pfad} antwortet ${r.status} in ${r.budget} s` +
        (r.inhalt ? ` und enthält „${r.inhalt}“` : '');

    test(titel, async ({ page }) => {
        const konsole: string[] = [];
        const gescheitert: string[] = [];
        page.on('console', (m) => {
            if (m.type() === 'error') konsole.push(m.text());
        });
        page.on('requestfailed', (q) => {
            gescheitert.push(`${q.url()} — ${q.failure()?.errorText}`);
        });

        const antwort = await page.goto(r.pfad, { waitUntil: 'load' });
        expect(antwort, 'keine Antwort').not.toBeNull();

        // Erste Antwort der Kette: bei erwartetem 3xx zählt die Weiterleitung.
        let anfrage = antwort!.request();
        while (anfrage.redirectedFrom()) anfrage = anfrage.redirectedFrom()!;
        const erste = await anfrage.response();
        const status =
            r.status >= 300 && r.status < 400
                ? (erste?.status() ?? 0)
                : antwort!.status();
        expect(status, 'HTTP-Status').toBe(r.status);

        const dauer = antwort!.request().timing().responseEnd / 1000;
        expect(dauer, `Zeitbudget ${r.budget} s`).toBeLessThanOrEqual(r.budget);

        if (r.inhalt) {
            // Wie grep -F in smoke.sh: der Quelltext der Antwort.
            const quelltext = await page.content();
            const hinweis = `Pflichtinhalt „${r.inhalt}“`;
            expect(quelltext, hinweis).toContain(r.inhalt);
        }
        if (r.status < 400) {
            expect(konsole, 'Konsolenfehler').toEqual([]);
            expect(gescheitert, 'gescheiterte Anfragen').toEqual([]);
        }
    });
}
