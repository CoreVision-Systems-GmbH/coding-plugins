<?php
/**
 * Theme-Funktionen: nur Einbindung. Verhalten gehört in Mu-Plugins (web/app/mu-plugins),
 * damit es einen Theme-Wechsel überlebt und kein Redakteur es abschalten kann.
 *
 * @package Site
 */

/**
 * Stylesheet laden — Block-Themes binden style.css nicht von selbst ein.
 *
 * @return void
 */
function site_stile(): void {
	wp_enqueue_style( 'site', get_stylesheet_uri(), array(), wp_get_theme()->get( 'Version' ) );
}
add_action( 'wp_enqueue_scripts', 'site_stile' );

/**
 * Dieselben Stile im Editor, damit Redakteure sehen, was Besucher sehen.
 *
 * @return void
 */
function site_editor_stile(): void {
	add_theme_support( 'editor-styles' );
	add_editor_style( 'style.css' );
}
add_action( 'after_setup_theme', 'site_editor_stile' );
