# Stack-Overlay Astro — Astro 7, statisches HTML

Ergänzt den Kern für öffentliche Content-Sites (Firmenseite, Landingpages, Doku, Blog). Hier stehen Firmenentscheidungen; Idiome kommen aus der offiziellen Astro-Dokumentation.

## 1. Zuständigkeiten & Architektur
- `output: 'static'`: Jede Seite wird beim Bau zu HTML. Es gibt keinen Anwendungsserver, keine Anfrage-Logik, keinen Zustand — nur Dateien hinter einem Webserver.
- Ablage: Seiten in `src/pages/`, das eine Basis-Layout in `src/layouts/Base.astro`, Bausteine in `src/components/`, Inhalte in `src/content/` (Collections), Bilder in `src/assets/`, unverarbeitete Dateien in `public/`. Die bestehende Ablage eines Repos hat Vorrang.
- **Kein Client-JavaScript ohne Grund.** Astro liefert von sich aus keins. Eine Insel (`client:*`) bekommt im Kommentar daneben die Begründung, warum HTML und CSS nicht reichen. Server Islands nur bei echtem Bedarf an Laufzeitdaten — und dann ist zu fragen, ob die Site noch statisch ist.
- Seiten-Metadaten sind Pflicht und laufen über das Basis-Layout: `title`, `description`, Canonical aus `site` + Pfad, `lang="de"`. Eine Seite ohne Layout gibt es nicht.
- Bilder über `astro:assets` (`<Image>`/`<Picture>` aus `src/assets/`): Größen, Formate und `loading` entstehen beim Bau. `public/` nur für Dateien, die unverändert durchgereicht werden (Favicon, `robots.txt`, Downloads).
- Inhalte als Content Collections mit Schema (`src/content.config.ts`), sobald es mehr als eine Handvoll gleichartiger Seiten gibt (Blog, Doku, Referenzen). Der Bau bricht ab, wenn ein Eintrag das Schema verletzt — das ist gewollt.
- Vor dem Code je Seite festhalten: `Adresse · Zweck · Titel/Beschreibung · Quelle des Inhalts`.

## 2. Grenzen (nicht verhandelbar)
- Keine Anmeldung, keine personenbezogenen Daten, keine Formulare mit Serverlogik, keine Datenbank. Braucht ein Vorhaben davon etwas, ist es keine Content-Site — dafür gilt `laravel`. Sollen Redakteure die Inhalte selbst im Browser pflegen, ist es `wordpress`.
- Keine Geheimnisse im Bau: Alles, was in `PUBLIC_*` oder im Quelltext steht, landet im ausgelieferten HTML.
- Keine fremden Skripte ohne Entscheidung (Tracking, Schriften von Drittservern, Einbettungen): Jedes lädt Daten des Besuchers zu einem Dritten — ein Datenschutz-Thema, kein Handgriff.
- Kein `set:html` mit Inhalten, die nicht aus dem eigenen Repo stammen.
- **Einwilligung nur, wenn es etwas einzuwilligen gibt.** Kein Consent-Banner ohne Tracker oder Drittdienst — ohne sie ist er Rauschen; mit ihnen lädt nichts vor dem Opt-in. Impressum (mit UID) und Datenschutzerklärung (mit Verantwortlichem und Betroffenenrechten) sind Pflichtseiten und stehen in `deploy/smoke.txt`.

## 3. Werkzeugkette
- Befehle aus dem Repo ermitteln (`CLAUDE.md`, `package.json`). Standard für neue Sites: `npm run check` = `astro check` (Typen und Vorlagen, einzeln `npm run check:types`) → `astro build` → `node --test` über `tests/**/*.test.mjs` (kein Test-Framework); dazu `npm audit --omit=dev --audit-level=high`. In `npm run check` und der CI auch `scripts/konfig-pruefen.sh` (`.env.example` nur `APP_VERSION`, `APP_DOMAIN`, `PUBLIC_*`) und `scripts/lizenzen-pruefen.sh` (Laufzeit-Abhängigkeiten gegen die Allow-Liste). Browser: `npm run e2e` (Playwright, `tests/e2e/`) gegen die Dev-Instanz aus dem Tailnet — drei Viewports, Rauchtest-Liste aus `deploy/smoke.txt`, Klick-Sweep, `retries: 0`.
- Abhängigkeiten mit Caret in `package.json`, festgezurrt durch `package-lock.json` (`npm ci`); Bumps als eigener PR (Dependabot `npm`).
- CI-Reihenfolge: `npm ci` → `npm run check:types` → `npm run build` → `npm test` → `scripts/komplexitaet-pruefen.sh` → `scripts/konfig-pruefen.sh` → `scripts/lizenzen-pruefen.sh` → `npm audit` — dieselben Schritte wie `npm run check`, einzeln benannt. Der Bau ist die eigentliche Prüfung: Er scheitert bei Schemaverstößen in Collections, fehlenden Bildern und fehlender `site`.
- Entwicklung unter Windows in Git Bash; `npm` liegt als Shell-Shim neben `npm.cmd` und wird gefunden. Node ≥ 22.12 ist Pflicht (Astro 7), Standard ist Node 24.

## 4. Betriebsvertrag
1. **Runtime:** Bau in `node:24-alpine`, Laufzeit `caddy:2-alpine` mit `file_server` aus `/srv` auf 8080. Der Edge-Caddy des Hosts terminiert TLS und verteilt nach Hostname; kein veröffentlichter Port, Container nur im Netz `edge`. **Härtung** (`compose.yaml`): Wurzeldateisystem schreibgeschützt (`read_only`, Schreibpfade als Volume oder tmpfs), `cap_drop: ALL`, `no-new-privileges`, Log-Rotation 5 × 20 MB je Container, Pflichtvariablen mit `:?` — fehlt ein Schlüssel in der `.env`, startet der Verbund nicht. Schreibbar sind nur der Caddy-Zustand (`/data`, `/config`, tmpfs mit uid/gid des Benutzers `web`) und `/tmp`.
2. **Konfiguration:** keine zur Laufzeit. `site` in `astro.config.mjs` ist Bauzeit — eine Site je Abbild; `PUBLIC_*` ebenso. Die `.env` der Instanz enthält nur `APP_VERSION`.
3. **Health:** `GET /healthz` antwortet direkt aus dem Caddy mit `{"status":"ok","version":"…"}`; der Compose-Healthcheck zeigt darauf (`wget` — `curl` gibt es im Abbild nicht).
4. **Logs:** Zugriffsprotokoll als JSON nach stderr, `/healthz` ausgenommen. Es gibt keine Cookies und keine Formulardaten, also auch keine PII.
5. **Version im Produkt:** Build-Arg `APP_IMAGE_VERSION` → `PUBLIC_APP_VERSION` beim Bau → `<meta name="app-version">` und Fußzeile im Layout; als ENV im Laufzeit-Abbild → `/healthz`.
6. **Lieferung:** wie im Kern — `release.yml` → GHCR (`X.Y.Z`, `X.Y`, `sha-…`), Server ziehen per `deploy/update.sh <tag>`, auf dem Prod-Server angestoßen von `rollout`. Keine Migration. Dev-Instanz auf dem Dev-Server: `deploy/dev.sh up` → `https://dev.<APP_DOMAIN>`. Nach dem Start prüft `deploy/smoke.sh` die Routen aus `deploy/smoke.txt` (Status, Zeitbudget, Pflichtinhalt): auf der Dev-Instanz eine Warnung, beim Update ein Abbruch mit Rückweg. Impressum (UID) und Datenschutz (Verantwortlicher) stehen in der Liste; das Gerüst liefert beide Seiten als Platzhalter.
7. **Daten:** keine. Deshalb keine Sicherung — `deploy/backup.sh` sagt das und endet mit 0; der Rückweg ist `deploy/update.sh <alter tag>`.
8. **Qualitätsgates:** `astro check` ohne Befund; jede Seite mit Titel und Beschreibung; `dist/` enthält `index.html`, `404.html` und `sitemap-index.xml`; kein Client-JavaScript ohne begründete Insel.

## 5. Fallen (stack-typisch)
- `site` fehlt oder zeigt noch auf die Platzhalter-Domain `<name>.invalid` → Canonicals und Sitemap zeigen ins Leere, Suchmaschinen indizieren die falsche Adresse. Das Layout bricht den Bau ab, wenn `site` ganz fehlt.
- `PUBLIC_*`-Variablen sind Bauzeit: Ein Wert in der `.env` auf dem Server ändert nichts am laufenden Abbild.
- Trailing Slash: Caddys `file_server` leitet `/seite` auf `/seite/` um. `trailingSlash: 'always'` hält den Dev-Server auf demselben Verhalten — sonst funktionieren lokal Links, die im Betrieb umgeleitet werden.
- Große Bilder in `public/` gehen unverändert an den Besucher und sprengen die Ladezeit — nach `src/assets/` und durch `astro:assets`.
- Astro 7 entfernt Leerraum nach JSX-Regeln (`compressHTML: 'jsx'`): `<span>a</span> <em>b</em>` verliert das Leerzeichen. Inline-Elemente nicht auf Leerraum zwischen Tags verlassen.
- Der Compiler weist unsauberes HTML ab (ungeschlossene Tags, falsche Verschachtelung) — Fehler beim Bau, nicht erst im Browser.
