<?php

/**
 * Sprachpakete für Kern, Plugins und Themes ins Abbild laden.
 *
 *     php docker/sprachpakete.php de_DE
 *
 * Liest composer.lock: die Fassung von WordPress (roots/wordpress) und alle Pakete
 * wp-plugin/*, wpackagist-plugin/*, wp-theme/*, wpackagist-theme/*. Für jedes lädt es die
 * Übersetzung der exakt installierten Fassung von translate.wordpress.org und entpackt sie
 * nach web/app/languages — dorthin, wo WordPress sie zur Laufzeit erwartet, aber wegen
 * DISALLOW_FILE_MODS nie selbst hinlegen dürfte.
 *
 * Nicht jedes Plugin hat eine Übersetzung: Fehlt sie (404), steht das in der Ausgabe und
 * der Bau läuft weiter. Fehlt die des Kerns oder scheitert das Netz, bricht der Bau ab —
 * eine englische Admin-Oberfläche fiele erst dem Redakteur auf.
 */

declare(strict_types=1);

$locale = $argv[1] ?? '';
if ($locale === '' || preg_match('/^[a-z]{2,3}(_[A-Za-z_]+)?$/', $locale) !== 1) {
    fwrite(STDERR, "Aufruf: php docker/sprachpakete.php <locale>   (z. B. de_DE)\n");
    exit(1);
}

$root = dirname(__DIR__);
$ziel = $root . '/web/app/languages';
$lock = json_decode((string) @file_get_contents($root . '/composer.lock'), true);
if (!is_array($lock) || !isset($lock['packages']) || !is_array($lock['packages'])) {
    fwrite(STDERR, "composer.lock fehlt oder ist unlesbar — vorher composer install.\n");
    exit(1);
}

/**
 * Lädt ein Zip und entpackt es in den Ordner. true bei Erfolg, false wenn es die
 * Übersetzung nicht gibt (404); jeder andere Fehler bricht ab.
 */
$laden = static function (string $url, string $ordner): bool {
    if (!is_dir($ordner) && !mkdir($ordner, 0755, true) && !is_dir($ordner)) {
        fwrite(STDERR, "Ordner nicht anlegbar: {$ordner}\n");
        exit(1);
    }

    $kontext = stream_context_create(['http' => ['ignore_errors' => true, 'timeout' => 60]]);
    $daten = file_get_contents($url, false, $kontext);
    $status = 0;
    foreach ($http_response_header ?? [] as $zeile) {
        if (preg_match('#^HTTP/\S+\s+(\d{3})#', $zeile, $treffer) === 1) {
            $status = (int) $treffer[1];
        }
    }

    if ($status === 404) {
        return false;
    }
    if ($daten === false || $status !== 200) {
        fwrite(STDERR, "Download gescheitert (HTTP {$status}): {$url}\n");
        exit(1);
    }

    $tmp = (string) tempnam(sys_get_temp_dir(), 'sprache');
    file_put_contents($tmp, $daten);
    $zip = new ZipArchive();
    if ($zip->open($tmp) !== true) {
        fwrite(STDERR, "Kein gültiges Zip: {$url}\n");
        exit(1);
    }
    $zip->extractTo($ordner);
    $zip->close();
    unlink($tmp);

    return true;
};

$kern = null;
$erweiterungen = [];
foreach ($lock['packages'] as $paket) {
    $name = (string) ($paket['name'] ?? '');
    $fassung = ltrim((string) ($paket['version'] ?? ''), 'v');
    if ($name === 'roots/wordpress') {
        $kern = $fassung;
    } elseif (preg_match('#^(wp|wpackagist)-(plugin|theme)/(.+)$#', $name, $treffer) === 1) {
        $erweiterungen[] = ['art' => $treffer[2], 'slug' => $treffer[3], 'fassung' => $fassung];
    }
}

if ($kern === null) {
    fwrite(STDERR, "roots/wordpress steht nicht in composer.lock.\n");
    exit(1);
}

$basis = 'https://downloads.wordpress.org/translation';

if (!$laden("{$basis}/core/{$kern}/{$locale}.zip", $ziel)) {
    fwrite(STDERR, "Kein Sprachpaket {$locale} für WordPress {$kern} bei wordpress.org.\n");
    exit(1);
}
echo "Sprachpaket {$locale}: WordPress {$kern}\n";

foreach ($erweiterungen as $e) {
    $url = "{$basis}/{$e['art']}/{$e['slug']}/{$e['fassung']}/{$locale}.zip";
    if ($laden($url, "{$ziel}/{$e['art']}s")) {
        echo "Sprachpaket {$locale}: {$e['art']} {$e['slug']} {$e['fassung']}\n";
    } else {
        echo "Sprachpaket {$locale}: {$e['art']} {$e['slug']} {$e['fassung']} — keine Übersetzung bei wordpress.org, übersprungen\n";
    }
}
