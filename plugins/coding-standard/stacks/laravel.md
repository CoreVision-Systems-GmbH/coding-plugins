# Stack-Overlay Laravel — Laravel 13 · Filament 5 · Inertia 3 + React 19

Ergänzt den Kern für Laravel-Repos. Framework-Idiome liefert Laravel Boost (Guidelines, Skills, `.ai/rules/`); hier stehen nur Firmenentscheidungen. Laravel ist das Arbeitspferd für alles Datennahe — Datenmodell, Rechte, Verwaltung, Nutzerkonten; die Stack-Wahl selbst trifft `/projekt-neu`.

## 1. Zuständigkeiten & Architektur
- **Laravel** ist autoritativ für Domänenregeln, Persistenz, Authentifizierung und Autorisierung, Validierung, Events/Queues/Jobs, Routing und Konfiguration.
- **Filament** für angemeldete interne Verwaltung: modellorientierte CRUD-Flächen, Tabellen, Formulare, Dashboards, ein Kundenportal als zweites Panel — solange Filaments Konventionen die UX tragen. Nicht für öffentliche oder hochfrequente Oberflächen und nicht für Design jenseits seiner Struktur; dort Eigenbau. Filament-Tenancy ist Single-DB und scoped nur im Panel — Jobs und Commands scopen selbst.
- **Inertia + React** für kunden- und produktseitige Oberflächen, wenn mindestens zwei Punkte zutreffen: Client-State dominiert (Drag & Drop, Karte, Editor, Latenz-Toleranz) · eine npm-Bibliothek ist unverzichtbar (Datagrid, Charts, MapLibre) · öffentliches Marken-UI mit Anspruch an die Ladezeit · React-Kompetenz für mindestens 18 Monate gesichert. Sonst Filament oder Livewire. Keine Mischung ohne klare Trennung nach Fläche.
- **Öffentlich** (ohne Anmeldung erreichbar, indexierbar): Seiten im Produkt als Inertia **mit SSR** je Route oder als Blade mit Cache — vollständiges HTML beim ersten Byte ist die einzige messbare Größe für Auffindbarkeit und Ladezeit. Reine Content-Sites (Firmenseite, Landingpages, Doku) gehören nicht in die Laravel-App, sondern in den Stack `astro` — oder in `wordpress`, wenn der Kunde die Inhalte selbst im Browser pflegt. Next.js ist kein Stack, sondern eine Ausnahme mit Auflagen (`stacks/nextjs.md`).
- **API** nur für einen eigenständigen Client (App, Integration, separates Frontend) — nie, um eine Inertia-Seite anzubinden. **Blade** für E-Mails, Dokumente und Kleinstansichten.
- Für jede neue nutzersichtbare Funktion vor dem Code festhalten:
  `Fläche: Filament | Inertia/React | Inertia SSR | API | Blade | keine UI · Nutzer: intern | Kunde | öffentlich | System · Begründung · gemeinsamer Anwendungsfall (Action/Service) · Autorisierung (Policy/Gate)`.
  Dieselbe Hauptfunktion nicht doppelt (Filament **und** React) ohne ausdrückliche Anforderung; bei echter Mehrdeutigkeit die Produktentscheidung erfragen.
- Filament und Inertia sind Adapter um dieselben Anwendungsfälle: `app/Actions` (Use Cases) · `app/Services` (Koordination, Integrationen) · `app/Policies` (Rechte für alle Flächen) · `app/Http/Requests` (Validierung) · dünne Controller · `app/Filament` (nur Darstellung) · `resources/js/pages|components` · `app/Jobs|Events`. Die bestehende Ablage des Repos hat Vorrang; keine Schichten auf Verdacht.

## 2. Grenzen (nicht verhandelbar)
- Keine Geschäftsregeln in React-Komponenten, Filament-Resources oder -Pages, Controllern oder Table-Callbacks.
- Autorisierung nie im Frontend; Inertia-Props und Client-State sind keine autoritative Eingabe.
- Nur die Daten serialisieren, die eine Seite braucht — keine ungefilterten Modelle, keine sensiblen Felder. Inertia gibt **alles** an den Client, was die Seite bekommt, auch was sie nicht anzeigt: `$hidden`, Resources oder DTOs, nie ganze Modelle.
- UI-Validierung verbessert die Rückmeldung, ersetzt nie die serverseitige.
- Kein globaler Client-State-Store ohne echten Bedarf; React typisiert, kein unerklärtes `any`; semantisches HTML, tastaturbedienbar.
- In Filament zuerst Resources, Schemas, Actions und Policies, bevor eigenes Livewire oder JavaScript entsteht.

## 3. Werkzeugkette & Fassungen
- Befehle aus `composer.json` und `package.json` des Repos ermitteln, nie erfinden. Üblich: Pint (`--test` in CI), Larastan, Pest, `npm run check` (Format + Lint), TypeScript-Check, Vite-Build.
- Nie `composer setup` in CI — es enthält `migrate`. Reihenfolge: `composer install` → `.env` aus `.env.example` → `key:generate` → `filament:assets` → Pint → Larastan → `composer audit` → Tests → `npm ci && npm run build` → TypeScript/ESLint. Keine PHP-Matrix; die Folgeversion als wöchentlicher `continue-on-error`-Job.
- Windows: PHP **mit** `intl` (Filament verlangt es). Bei HTTP 500 in Filament-Tests zuerst `php -m | grep intl`.
- Larastan auf Stufe 8 braucht `--memory-limit=1G` im `types:check`-Script; mit den voreingestellten 128 MB stürzt der Parallel-Worker ab.
- **Fassungen (neu):** PHP 8.4 · `laravel/framework ^13` · `filament/filament ^5.4` (erste Fassung mit Laravel 13) · `livewire/livewire ^4.1` · `inertiajs/inertia-laravel ^3` · `@inertiajs/react ^3` mit React 19 · Pest 5 (verlangt PHP 8.4) · Tailwind 4. `laravel/wayfinder` ist 0.1.x und offiziell Beta: nur für Routen, keine `next`-Generatoren, Fassung pinnen. Das Starter-Kit wird kopiert, nicht aktualisiert.
- **Rhythmus:** Laravel-Major jährlich im ersten Quartal → Upgrade vor dem Bugfix-Ende der Vorfassung (rund fünf Monate nach dem Major); Bestand nie stillschweigend heben, immer eigener PR mit den Upgrade-Skripten (`boost`, `filament-v5`). Filament-Major nur zusammen mit dem Livewire-Major. Jedes Filament-Plugin vor Aufnahme auf ein 5.x-Tag prüfen, Plugin-Zahl klein halten.

## 4. Betriebsvertrag
1. **Runtime:** `dunglas/frankenphp:1-php8.4` klassisch (kein Octane, kein Worker-Modus). Ein Image, drei Rollen: `app` (HTTP auf 8080), `worker` (`queue:work --max-time=3600`), `scheduler` (`schedule:work`); `db` daneben. Der Edge-Caddy des Hosts terminiert TLS, die App veröffentlicht keinen Port, `TrustProxies` steht auf dem Docker-Netz.
2. **SSR** nur, wenn es öffentliche Inertia-Seiten gibt: vierte Rolle `ssr` aus demselben Image (`php artisan inertia:start-ssr`, Node ≥ 22 im Image, `inertia.ssr.url` auf den Dienstnamen, `ensure_bundle_exists`), Healthcheck `inertia:check-ssr`; Admin und Dashboards per `Inertia::withoutSsr()` ausgenommen; nach einem Update startet `ssr` mit. In Tests `INERTIA_SSR_ENABLED=false`.
3. **ENV:** `env()` ausschließlich in `config/**`. `.env.example` ist das Schema mit Kommentar je Schlüssel. `APP_KEY` je Instanz einmal erzeugen → KeePassXC, nie ins Image oder Repo. Kundenspezifisches nur über ENV und Pennant-Flags — kein Kundenzweig, kein Kundenimage.
4. **Generierte Artefakte** (`public/build/**`, `public/css/filament/**`, `public/js/filament/**`, `public/vendor/**`) als eine Liste identisch in `.gitignore`, `vp check`, Pint- und Larastan-Excludes und `vite.config.ts` — dort in `fmt.ignorePatterns` **und** `lint.ignorePatterns`.
5. **Filament-Sicherheit:** Das Panel nutzt nicht die `web`-Gruppe. App-weite Sicherheits-Middleware zusätzlich im Panel-Provider registrieren, mit `isPersistent: true` (sonst nur beim ersten Seitenaufruf). Policy je Resource; `FilamentUser` für den Zugang.
6. **Caches zur Laufzeit:** `php artisan optimize` im Entrypoint nach dem Laden der ENV, nicht im Image. Nach einem Update `php artisan reload`.
7. **Qualitätsgates:** Larastan Level 7 (Bestand) bzw. 8 (neu); `pest --type-coverage --min=95`; Policy-Tests paarweise Pflicht; Browser-Tests (Pest 5 Browser-Plugin + Playwright) nur für kritische Wege, als Nightly.
8. **Version im Produkt:** Build-Arg `APP_IMAGE_VERSION` → `config('app.version')` → Footer beider Oberflächen. Die Instanz pinnt den Image-Tag über `APP_VERSION` in ihrer `.env`.
9. **Lieferung:** `release.yml` baut aus `vX.Y.Z` nach GHCR (`X.Y.Z`, `X.Y`, `sha-…`, kein `latest`). Server ziehen per `deploy/update.sh <tag>` (Backup → Pull → `migrate --force` → `up -d --wait` → `reload` → `/up`), auf dem Prod-Server angestoßen von `rollout` (sofort oder zum Termin), der die Lieferdateien des Tags nach `/opt/apps/<app>/` holt; fremde Images sind gepinnt. Entwickelt wird auf dem Dev-Server: `deploy/dev.sh up` baut aus dem Arbeitsstand mit eigener Datenbank unter `https://dev.<APP_DOMAIN>`.
10. **Migrationen:** expand/contract — neue Spalten `nullable` oder mit Default, `DROP` und Umbenennung erst im Folgerelease, keine Datenmassen in Migrationen (Job oder Command).
11. **Boost:** Sein Block in `CLAUDE.md` bleibt committed und wird nur von `boost:update` gepflegt; `.ai/rules/` committen.

## 5. Fallen (stack-typisch)
- `config:cache` liefert `null` für jedes `env()` außerhalb von `config/`.
- Hinter dem Edge-Caddy ohne `TrustProxies`: `http://`-URLs, kaputte Redirects und Cookies.
- `Storage::url()` absolut ausliefern bricht Mehrfach-Hostnamen (WAN + Tailnet).
- Zeitzone nie hart `UTC`; Prüfungen wie „nicht in der Zukunft“ lesen dieselbe Uhr wie das Formular.
- Livewire-Anfragen laufen über die `web`-Gruppe; Panel-Middleware ohne `isPersistent` greift dort nicht.
- Laravel 13: `PreventRequestForgery` ersetzt `VerifyCsrfToken` — Tests mit `withoutMiddleware` nachziehen; `cache.serializable_classes` ist aus, Objekte im Cache brauchen eine Allow-List; `upsert()` verlangt `uniqueBy`.
- Livewire 4: `wire:model` hört nur auf direkte Events (`.deep` für verschachtelte); `.blur`/`.change` synchen jetzt auch den Client-State (`.live.blur` für das alte Verhalten); Komponenten-Tags müssen geschlossen sein.
- Wayfinder: ein abgeschaltetes Fortify-Feature nimmt seine Route mit — der Frontend-Build bricht an einem fehlenden Export, nicht an einer klaren Meldung.
