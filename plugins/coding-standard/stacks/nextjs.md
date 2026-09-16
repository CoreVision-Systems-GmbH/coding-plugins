# Stack-Overlay Next.js — Ausnahme mit Auflagen

Next.js ist **kein** Stack des Firmenstandards: `/projekt-neu` bietet ihn nicht an. Dieses Overlay gilt für den Bestand (z. B. `pcn-projektmanagement`) und für die Ausnahme, die der Nutzer ausdrücklich entscheidet, wenn **alle drei** Bedingungen zutreffen:

1. Öffentlich indexierbar **und** ein bezifferbares Conversion- oder Umsatzziel.
2. Eine Anforderung, die Inertia SSR und Astro nicht liefern: Streaming/Partial Prerendering, ISR über mehrere Instanzen, personalisierte öffentliche Seiten unter Lastspitzen.
3. Budget für den Zweitbetrieb: eigener Node-Prozess, monatlicher Patch-Takt, eigene Auth-Grenze.

Für Firmenseite, Landingpages, Doku und Blog gilt `astro` (pflegt der Kunde die Inhalte selbst: `wordpress`); für Kundenportale mit Anmeldung `laravel` mit Inertia SSR. Auffindbarkeit und Ladezeit sind kein Grund: Google belohnt vollständiges HTML und gute Core Web Vitals, nicht ein Framework.

## 1. Zuständigkeiten & Architektur
- App Router mit React Server Components; keine Mischung mit dem Pages Router. `proxy.ts` (ehemals `middleware.ts`) ist kein Sicherheitsrand: Autorisierung passiert in Route Handlers, Server Actions und der Datenzugriffsschicht — an jeder Stelle einzeln.
- **Identitätsquelle:** Gibt es ein Laravel-Backend, bleibt Laravel die Identitätsquelle (Sanctum-Cookie auf gemeinsamer Top-Level-Domain); kein zweiter Nutzerbestand. Steht Next.js allein (Bestand mit better-auth), bleibt die Auth-Bibliothek gepinnt, und Plugins (SSO, OIDC, MCP) werden nur geladen, wenn sie genutzt werden.
- Datenzugriff an einer Stelle (`lib/db`, Drizzle); Server Actions validieren Eingaben mit Schema, nie über Props oder Client-State.

## 2. Grenzen (nicht verhandelbar)
- Keine Geheimnisse in `NEXT_PUBLIC_*` — alles darin liegt im Browser.
- Server Actions und Route Handler prüfen Session und Rechte selbst; der Proxy ist zusätzliche, nie einzige Schranke.
- Kein `dangerouslySetInnerHTML` mit Nutzerdaten; keine Redirects aus Query-Parametern ohne Allow-List.
- Nur die Active-LTS-Linie; ein Sicherheits-Release wird innerhalb von sieben Tagen eingespielt (monatliches, vorangekündigtes Programm seit Juli 2026).

## 3. Werkzeugkette
- Befehle aus `package.json`: ESLint, `tsc --noEmit`, Tests (sofern vorhanden), `next build`. `npm ci` in CI, Lockfile committed.
- Dependabot: `next`, `react`, Auth-Bibliothek — minor/patch gebündelt, major einzeln; Sicherheits-Bumps sofort und außerhalb des Wochenrhythmus.

## 4. Betriebsvertrag
1. **Runtime:** `output: 'standalone'`, Image `node:24-alpine` mit Non-root-Benutzer, `public/` und `.next/static` ausdrücklich ins Image kopieren (standalone lässt beide weg), HTTP auf 8080 hinter dem Edge-Caddy, kein veröffentlichter Port. Bewusst **eine** Instanz — mehrere Instanzen brauchen `cacheHandler` (Redis), `refreshTags`, festen `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` und `deploymentId`.
2. **Proxy:** Der Edge-Caddy streicht `x-middleware-subrequest` aus eingehenden Anfragen. Streaming-Antworten (chunked, `text/event-stream`) flusht Caddy von selbst; `flush_interval -1` nur als Absicherung, keine `response_buffers`.
3. **Bilder:** Image Optimization aus oder `.next/cache` als Volume; AVIF-Optimierung bleibt aus.
4. **ENV:** Laufzeit-Konfiguration nur über ENV zur Laufzeit; `NEXT_PUBLIC_*` ist Bauzeit. `.env.example` als Schema mit Kommentar je Schlüssel.
5. **Health:** `GET /healthz` als Route Handler mit Fassung; Compose-Healthcheck darauf.
6. **Version im Produkt:** Build-Arg `APP_IMAGE_VERSION` → ENV → `/healthz` und Footer.
7. **Lieferung:** wie im Kern — `release.yml` → GHCR, `deploy/update.sh <tag>`; Drizzle-Migrationen additiv, Sicherung davor.
8. **Qualitätsgates:** Typen und Lint grün; kein Merge mit offenen `npm audit`-Befunden ab `high`.

## 5. Fallen (stack-typisch)
- `standalone` kopiert `public/` und `.next/static` nicht — die Site läuft, aber ohne Bilder und Stile.
- Caching ist seit 16 „dynamic by default“; wer `cacheComponents` einschaltet, bekommt Build-Fehler an jeder ungekennzeichneten dynamischen Stelle.
- Version Skew nach einem Update: offene Tabs rufen alte Server Actions — `deploymentId` setzen oder Nutzer neu laden lassen.
- Ein Proxy mit Puffer macht aus Streaming einen Wasserfall. Caddy flusht bei unbekannter Content-Length von selbst, andere Proxies (nginx, Traefik mit Buffering) nicht — beim Wechsel prüfen.
