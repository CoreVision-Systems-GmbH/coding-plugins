<?php

/**
 * Einstieg für Besucher: lädt WordPress mit dem aktiven Theme.
 * Nach dem Muster von Roots Bedrock (MIT). Nicht bearbeiten.
 */
define('WP_USE_THEMES', true);
require __DIR__ . '/wp/wp-blog-header.php';
