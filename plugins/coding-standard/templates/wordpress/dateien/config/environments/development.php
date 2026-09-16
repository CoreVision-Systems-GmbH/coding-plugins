<?php

/**
 * Abweichungen für WP_ENV=development (lokaler Verbund, compose.dev.yaml): Fehler
 * sichtbar, Abfragen mitgeschrieben. Alles andere bleibt wie in Produktion — was lokal
 * anders läuft, lässt sich auf dem Server nicht prüfen. Keine Indexierung außerhalb
 * von Produktion erzwingt das Mu-Plugin firmenstandard.
 */

use Roots\WPConfig\Config;

Config::define('WP_DEBUG', true);
Config::define('WP_DEBUG_DISPLAY', true);
Config::define('WP_DISABLE_FATAL_ERROR_HANDLER', true);
Config::define('SCRIPT_DEBUG', true);
Config::define('SAVEQUERIES', true);

ini_set('display_errors', '1');
