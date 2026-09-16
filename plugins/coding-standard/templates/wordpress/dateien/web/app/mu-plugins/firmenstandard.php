<?php
/**
 * Plugin Name: Firmenstandard
 * Description: Betriebsvertrag der Site — /healthz, Fassung im Produkt, Härtung. Gilt in jeder Instanz; ein Redakteur kann es nicht abschalten.
 * Version: 1.0.0
 * Author: {{COMPANY}}
 *
 * Mu-Plugin (must-use): wird vor Theme und Plugins geladen. Was hier steht, gehört zum
 * Betrieb, nicht zur Site. Site-Logik (eigene Inhaltstypen, Blöcke, Muster) kommt in
 * eigene Mu-Plugins daneben — nie in die functions.php des Themes.
 *
 * @package Firmenstandard
 */

/**
 * Die ausgelieferte Fassung: Build-Arg APP_IMAGE_VERSION des Abbilds, sonst „dev“.
 *
 * @return string Fassung, z. B. „1.2.0“.
 */
function firmenstandard_fassung(): string {
	$fassung = getenv( 'APP_IMAGE_VERSION' );

	return is_string( $fassung ) && '' !== $fassung ? $fassung : 'dev';
}

/**
 * GET /healthz — beweist PHP und Datenbank und nennt die Fassung.
 *
 * Läuft, sobald die Mu-Plugins geladen sind: Die Datenbankverbindung steht dann schon,
 * Theme und Plugins sind noch nicht dran. Compose-Healthcheck und deploy/update.sh
 * zeigen hierher.
 *
 * @return void
 */
function firmenstandard_healthz(): void {
	$pfad = isset( $_SERVER['REQUEST_URI'] ) ? sanitize_text_field( wp_unslash( $_SERVER['REQUEST_URI'] ) ) : '';

	if ( '/healthz' !== strtok( $pfad, '?' ) ) {
		return;
	}

	global $wpdb;

	if ( ! $wpdb->check_connection( false ) ) {
		wp_send_json( array( 'status' => 'db-unreachable' ), 503 );
	}

	wp_send_json(
		array(
			'status'  => 'ok',
			'version' => firmenstandard_fassung(),
		),
		200
	);
}
add_action( 'muplugins_loaded', 'firmenstandard_healthz' );

/**
 * Fassung im Produkt: als Meta-Tag im HTML jeder Seite.
 *
 * @return void
 */
function firmenstandard_meta_fassung(): void {
	printf( '<meta name="app-version" content="%s">' . "\n", esc_attr( firmenstandard_fassung() ) );
}
add_action( 'wp_head', 'firmenstandard_meta_fassung', 1 );

/**
 * Rechte Fußzeile des Admins: statt der WordPress-Fassung die der Site.
 *
 * @return string Text der Fußzeile.
 */
function firmenstandard_admin_fassung(): string {
	return esc_html( 'Fassung ' . firmenstandard_fassung() );
}
add_filter( 'update_footer', 'firmenstandard_admin_fassung', 11 );

// Härtung, die kein Plugin braucht.
// XML-RPC ist ein alter Fernzugang und heute nur Angriffsfläche (Brute-Force, Pingbacks).
add_filter( 'xmlrpc_enabled', '__return_false' );
// Kein Hinweis auf die WordPress-Fassung im HTML.
remove_action( 'wp_head', 'wp_generator' );
add_filter( 'the_generator', '__return_empty_string' );

/**
 * Nutzerliste über REST nur angemeldet — sonst liefert /wp-json/wp/v2/users die
 * Anmeldenamen der Redakteure an jeden.
 *
 * @param array<string, mixed> $endpoints Registrierte REST-Endpunkte.
 * @return array<string, mixed> Endpunkte ohne die Nutzerliste für Anonyme.
 */
function firmenstandard_rest_nutzer( array $endpoints ): array {
	if ( is_user_logged_in() ) {
		return $endpoints;
	}

	unset( $endpoints['/wp/v2/users'], $endpoints['/wp/v2/users/(?P<id>[\d]+)'] );

	return $endpoints;
}
add_filter( 'rest_endpoints', 'firmenstandard_rest_nutzer' );

// Außerhalb von Produktion keine Indexierung — egal, was in den Einstellungen steht.
if ( defined( 'WP_ENV' ) && 'production' !== WP_ENV ) {
	add_filter( 'pre_option_blog_public', '__return_zero' );
}
