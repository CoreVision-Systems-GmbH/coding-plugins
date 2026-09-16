<?php

/**
 * Strukturprüfung — was WordPress erst zur Laufzeit merken würde, hier vorher.
 *
 *     composer test
 *
 * Ohne Datenbank, ohne Framework. Jede Zusicherung eine Zeile; bei Befund endet das
 * Skript mit Ausgangswert 1 und nennt, was fehlt.
 */

declare(strict_types=1);

$root = dirname(__DIR__);
$befunde = [];

$sicher = static function (bool $bedingung, string $meldung) use (&$befunde): void {
    if ($bedingung) {
        echo "ok     {$meldung}\n";
        return;
    }
    echo "FEHLER {$meldung}\n";
    $befunde[] = $meldung;
};

$lesen = static fn (string $pfad): string => (string) @file_get_contents($pfad);

// ---------------------------------------------------------------- Theme
$theme = $root . '/web/app/themes/site';
$pflicht = [
    'style.css',
    'theme.json',
    'functions.php',
    'templates/index.html',
    'templates/singular.html',
    'templates/404.html',
    'parts/header.html',
    'parts/footer.html',
];
foreach ($pflicht as $datei) {
    $sicher(is_file("{$theme}/{$datei}"), "Theme: {$datei} vorhanden");
}

$style = $lesen("{$theme}/style.css");
$sicher(preg_match('/^Theme Name:\s*\S/m', $style) === 1, 'Theme: style.css trägt „Theme Name“');
$sicher(preg_match('/^Version:\s*\d/m', $style) === 1, 'Theme: style.css trägt eine Fassung');

$json = json_decode($lesen("{$theme}/theme.json"), true);
$sicher(is_array($json) && ($json['version'] ?? 0) === 3, 'Theme: theme.json ist gültiges JSON in Fassung 3');
$sicher(
    is_array($json) && isset($json['templateParts']) && is_array($json['templateParts'])
        && count($json['templateParts']) >= 2,
    'Theme: theme.json registriert Kopf und Fuß'
);

// Block-Vorlagen sind HTML mit Block-Kommentaren — PHP darin läuft nie.
$vorlagen = array_merge(glob("{$theme}/templates/*.html") ?: [], glob("{$theme}/parts/*.html") ?: []);
foreach ($vorlagen as $vorlage) {
    $name = basename(dirname($vorlage)) . '/' . basename($vorlage);
    $sicher(!str_contains($lesen($vorlage), '<?php'), "Theme: kein PHP in {$name}");
    $sicher(str_contains($lesen($vorlage), '<!-- wp:'), "Theme: {$name} enthält Blöcke");
}

// ------------------------------------------------------------ Mu-Plugin
$mu = $root . '/web/app/mu-plugins/firmenstandard.php';
$sicher(is_file($mu), 'Mu-Plugin firmenstandard.php vorhanden');
$sicher(str_contains($lesen($mu), '/healthz'), 'Mu-Plugin beantwortet /healthz');

// ---------------------------------------------------------- ENV-Schema
// Jeder Schlüssel, den die Konfiguration liest, steht in .env.example — sonst fehlt er
// auf dem Server, und deploy/install.sh kann es nicht merken.
$konfig = '';
$konfigdateien = array_merge(
    glob("{$root}/config/*.php") ?: [],
    glob("{$root}/config/environments/*.php") ?: []
);
foreach ($konfigdateien as $datei) {
    $konfig .= $lesen($datei);
}
preg_match_all("/env\\('([A-Z][A-Z0-9_]*)'\\)/", $konfig, $treffer);
$gelesen = array_values(array_unique($treffer[1]));

$beispiel = $lesen("{$root}/.env.example");
preg_match_all('/^([A-Z][A-Z0-9_]*)=/m', $beispiel, $treffer);
$schema = $treffer[1];

// Schlüssel, die die Konfiguration ableitet, wenn sie fehlen.
$optional = ['WP_SITEURL'];

foreach ($gelesen as $schluessel) {
    $sicher(
        in_array($schluessel, $schema, true) || in_array($schluessel, $optional, true),
        "ENV: {$schluessel} (config/) steht in .env.example"
    );
}

// Umgekehrt: kein toter Schlüssel im Schema. Was die Konfiguration nicht liest, muss
// compose.yaml oder ein Deploy-Skript lesen.
$anderswo = $konfig . $lesen("{$root}/compose.yaml");
foreach (glob("{$root}/deploy/*.sh") ?: [] as $datei) {
    $anderswo .= $lesen($datei);
}
foreach ($schema as $schluessel) {
    $sicher(str_contains($anderswo, $schluessel), "ENV: {$schluessel} (.env.example) wird gelesen");
}

// -------------------------------------------------------------- Betrieb
$sicher(
    preg_match('#^path:\s*web/wp\s*$#m', $lesen("{$root}/wp-cli.yml")) === 1,
    'wp-cli.yml zeigt auf web/wp'
);

$composer = json_decode($lesen("{$root}/composer.json"), true);
$wordpress = is_array($composer) ? (string) ($composer['require']['roots/wordpress'] ?? '') : '';
$sicher(
    preg_match('/^~\d+\.\d+\.0$/', $wordpress) === 1,
    'composer.json: roots/wordpress auf eine Nebenfassung gepinnt (~X.Y.0)'
);

echo "\n";
if ($befunde !== []) {
    echo count($befunde) . " Befund(e).\n";
    exit(1);
}
echo "Alle Zusicherungen erfüllt.\n";
