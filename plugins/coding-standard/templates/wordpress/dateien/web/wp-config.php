<?php

/**
 * Nicht bearbeiten — die Konfiguration steht in config/. Diese Datei muss hier liegen,
 * weil WordPress seine wp-config.php im eigenen Ordner oder eine Ebene darüber sucht.
 * Nach dem Muster von Roots Bedrock (MIT).
 */
require_once dirname(__DIR__) . '/vendor/autoload.php';
require_once dirname(__DIR__) . '/config/application.php';
require_once ABSPATH . 'wp-settings.php';
