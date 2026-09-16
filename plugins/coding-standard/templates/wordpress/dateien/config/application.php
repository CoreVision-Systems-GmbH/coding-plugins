<?php

/**
 * Konfiguration der Site — die eine Stelle, an der ENV gelesen wird.
 *
 * Nach dem Muster von Roots Bedrock (MIT). Werte kommen ausschließlich aus der Umgebung:
 * auf dem Server aus der .env des Verbunds (compose.yaml, env_file), lokal aus einer .env
 * im Projektordner. Umgebungsspezifisches steht in config/environments/<WP_ENV>.php und
 * wird danach geladen. Kein wp-config.php mit Werten, nirgends.
 */

use Roots\WPConfig\Config;

use function Env\env;

Env\Env::$options = Env\Env::CONVERT_BOOL
    | Env\Env::CONVERT_NULL
    | Env\Env::CONVERT_INT
    | Env\Env::STRIP_QUOTES
    | Env\Env::LOCAL_FIRST;

$root_dir = dirname(__DIR__);
$webroot_dir = $root_dir . '/web';

// Eine .env gibt es nur lokal. Im Abbild kommen die Werte aus der Umgebung des
// Containers; die Datei bleibt bewusst draußen (.dockerignore).
if (file_exists($root_dir . '/.env')) {
    $repository = Dotenv\Repository\RepositoryBuilder::createWithNoAdapters()
        ->addAdapter(Dotenv\Repository\Adapter\EnvConstAdapter::class)
        ->addAdapter(Dotenv\Repository\Adapter\PutenvAdapter::class)
        ->immutable()
        ->make();

    Dotenv\Dotenv::create($repository, $root_dir, ['.env'], false)->load();
}

// Ein fehlender Pflichtwert bricht mit klarer Meldung ab — statt einer leeren Site oder
// einer Anmeldung, die ins Leere läuft.
foreach (['WP_HOME', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'] as $pflicht) {
    if (!env($pflicht)) {
        http_response_code(500);
        exit('Konfiguration unvollständig: ' . $pflicht . ' fehlt in der Umgebung (.env).');
    }
}

/**
 * Umgebung: production oder development. Alles außer production zeigt Fehler und
 * sperrt Suchmaschinen aus (config/environments/, Mu-Plugin firmenstandard).
 */
define('WP_ENV', env('WP_ENV') ?: 'production');

if (!defined('WP_ENVIRONMENT_TYPE')) {
    $bekannt = ['production', 'staging', 'development', 'local'];
    Config::define('WP_ENVIRONMENT_TYPE', in_array(WP_ENV, $bekannt, true) ? WP_ENV : 'production');
}

/**
 * Adressen: WP_HOME ist die öffentliche Adresse der Site, WordPress selbst liegt
 * darunter in /wp. Beide schlagen die Werte in der Datenbank — ein Umzug heißt ENV
 * ändern, nicht wp_options.
 */
Config::define('WP_HOME', env('WP_HOME'));
Config::define('WP_SITEURL', env('WP_SITEURL') ?: env('WP_HOME') . '/wp');

/**
 * Inhaltsverzeichnis: web/app statt wp-content.
 */
Config::define('CONTENT_DIR', '/app');
Config::define('WP_CONTENT_DIR', $webroot_dir . Config::get('CONTENT_DIR'));
Config::define('WP_CONTENT_URL', Config::get('WP_HOME') . Config::get('CONTENT_DIR'));

/**
 * Datenbank: MariaDB, Dienstname aus compose.yaml.
 */
Config::define('DB_NAME', env('DB_NAME'));
Config::define('DB_USER', env('DB_USER'));
Config::define('DB_PASSWORD', env('DB_PASSWORD'));
Config::define('DB_HOST', env('DB_HOST') ?: 'db');
Config::define('DB_CHARSET', 'utf8mb4');
Config::define('DB_COLLATE', '');
$table_prefix = env('DB_PREFIX') ?: 'wp_';

/**
 * Schlüssel und Salts — je Instanz einmal erzeugt, im KeePassXC-Tresor. Sie signieren
 * Cookies und Nonces; ändern meldet alle Nutzer ab.
 */
Config::define('AUTH_KEY', env('AUTH_KEY'));
Config::define('SECURE_AUTH_KEY', env('SECURE_AUTH_KEY'));
Config::define('LOGGED_IN_KEY', env('LOGGED_IN_KEY'));
Config::define('NONCE_KEY', env('NONCE_KEY'));
Config::define('AUTH_SALT', env('AUTH_SALT'));
Config::define('SECURE_AUTH_SALT', env('SECURE_AUTH_SALT'));
Config::define('LOGGED_IN_SALT', env('LOGGED_IN_SALT'));
Config::define('NONCE_SALT', env('NONCE_SALT'));

/**
 * Betriebsentscheidungen — nicht verhandelbar (stacks/wordpress.md).
 */

// Kein Code aus dem Admin: keine Plugin- und Theme-Installation, kein Datei-Editor,
// keine Auto-Updates. Core, Plugins und Sprachpakete kommen über Composer und das
// Abbild — auch lokal, sonst läuft die Entwicklung vom Betrieb weg.
Config::define('DISALLOW_FILE_MODS', true);
Config::define('DISALLOW_FILE_EDIT', true);
Config::define('AUTOMATIC_UPDATER_DISABLED', true);
Config::define('WP_AUTO_UPDATE_CORE', false);

// Zeitgesteuertes läuft im Dienst `cron` (wp cron event run), nicht auf Besucheranfragen.
Config::define('DISABLE_WP_CRON', true);

// Das eine Theme der Site: nach der Erstinstallation aktiv und der Rückfall.
Config::define('WP_DEFAULT_THEME', 'site');

// Revisionen begrenzen — sonst wächst wp_posts mit jedem Speichern.
Config::define('WP_POST_REVISIONS', 10);
Config::define('CONCATENATE_SCRIPTS', false);

/**
 * Fehler: nie im Browser; in Produktion nur nach stderr (docker/php.ini).
 */
Config::define('WP_DEBUG', false);
Config::define('WP_DEBUG_DISPLAY', false);
Config::define('WP_DEBUG_LOG', false);
Config::define('SCRIPT_DEBUG', false);
ini_set('display_errors', '0');

/**
 * Hinter dem Edge-Caddy: TLS endet dort, die Anfrage kommt als HTTP an. Ohne diese
 * Weiche hält WordPress die Site für unverschlüsselt — Umleitungsschleife auf
 * /wp/wp-admin, Cookies ohne secure. Nicht entfernen.
 */
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
}

$env_config = __DIR__ . '/environments/' . WP_ENV . '.php';

if (file_exists($env_config)) {
    require_once $env_config;
}

Config::apply();

if (!defined('ABSPATH')) {
    define('ABSPATH', $webroot_dir . '/wp/');
}
