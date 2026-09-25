import { defineConfig, devices } from '@playwright/test';

// Browser-Prüfung gegen die Dev-Instanz — aus dem Tailnet, nicht aus der
// GitHub-CI (dev.* ist dort nicht erreichbar).
// Aufruf: E2E_BASE_URL=https://dev.<APP_DOMAIN> npm run e2e
//
// Drei Viewports, weil die meisten Layoutfehler erst auf dem Handy sichtbar
// werden — alle drei mit Chromium, damit ein einziges `npx playwright install
// chromium` reicht (das iPad-Gerät brächte sonst WebKit mit).
// retries bleiben 0: Ein Test, der beim zweiten Mal grün wird, ist rot (flaky).
// Für die Nachtprüfung auf dem Dev-Server E2E_REPEAT=2 — jeder Test läuft
// zweimal, ein Unterschied zwischen beiden Läufen ist der Befund. Das
// JSON-Ergebnis liegt unter tests/e2e/ergebnis.json.

const wiederholungen = Number.parseInt(process.env.E2E_REPEAT ?? '1', 10);
if (!Number.isInteger(wiederholungen) || wiederholungen < 1) {
    throw new Error('E2E_REPEAT muss eine ganze Zahl ab 1 sein.');
}

export default defineConfig({
    testDir: '.',
    timeout: 30_000,
    retries: 0,
    repeatEach: wiederholungen,
    workers: 2,
    reporter: [['list'], ['json', { outputFile: 'ergebnis.json' }]],
    use: {
        baseURL: process.env.E2E_BASE_URL ?? 'http://127.0.0.1:8080',
        trace: 'retain-on-failure',
        locale: 'de-AT',
        timezoneId: 'Europe/Vienna',
    },
    projects: [
        {
            name: 'desktop',
            use: {
                ...devices['Desktop Chrome'],
                viewport: { width: 1440, height: 900 },
            },
        },
        {
            name: 'tablet',
            use: { ...devices['iPad (gen 7)'], defaultBrowserType: 'chromium' },
        },
        {
            name: 'mobil',
            use: { ...devices['Pixel 7'] },
        },
    ],
});
