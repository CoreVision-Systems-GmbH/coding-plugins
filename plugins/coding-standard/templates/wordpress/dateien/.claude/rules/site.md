---
paths: ['web/app/**', 'config/**']
---

# Theme, Mu-Plugins und Konfiguration (WordPress, Bedrock-Layout)

- **Code oder Inhalt?** Theme, Mu-Plugins, Konfiguration und die Plugin-Auswahl sind Code:
  Repo, Review, Release. Seiten, Beiträge, Medien, Menüs und Einstellungen sind Inhalt:
  Datenbank und Uploads, gehören dem Redakteur — nie ins Repo, nie im Code hart verdrahtet.
- **Verhalten in Mu-Plugins, Darstellung im Theme.** Eigene Inhaltstypen, Blöcke, Muster
  und Hooks kommen als Datei nach `web/app/mu-plugins/`, nicht in die `functions.php`. Sie
  überleben einen Theme-Wechsel, und kein Redakteur kann sie abschalten.
- **Kein Plugin ohne Entscheidung.** Jedes Plugin steht mit Zweck, Pflegestand und
  Begründung in einem ADR und kommt per Composer (`wp-plugin/<slug>` aus
  repo.wp-packages.org). Keine Page-Builder, nichts, was Code aus dem Admin nachlädt.
  Core-Blöcke und ein Muster (Pattern) sind meist die Antwort.
- **Kein Code aus dem Admin.** `DISALLOW_FILE_MODS` bleibt an, auch lokal. Wer im Admin ein
  Plugin „installieren“ will, hat die Frage falsch gestellt.
- **WordPress-Coding-Standards** für Theme und Mu-Plugins (`composer lint`): Tabs, Yoda,
  jede Ausgabe mit `esc_*`, jede Eingabe geprüft, Präfix `site_` bzw. `firmenstandard_`
  für alles Globale. `config/` und `tests/` folgen PSR-12.
- **ENV nur in `config/application.php`.** Kein `getenv()` im Theme oder in Mu-Plugins;
  Werte laufen über Konstanten aus der Konfiguration. Einzige Ausnahme: die Fassung
  (`APP_IMAGE_VERSION`) im Mu-Plugin firmenstandard.
- **Block-Theme:** Vorlagen unter `templates/`, Kopf und Fuß unter `parts/`, Gestaltung in
  `theme.json`. Kein PHP in Vorlagen, kein eigenes CSS ohne das Warum daneben.
- **Keine fremden Skripte ohne Entscheidung** (Tracking, Schriften von Drittservern,
  Einbettungen) — jedes lädt Daten des Besuchers zu einem Dritten: ein Datenschutz-Thema,
  kein Handgriff. Schriften lokal.
- Alle sichtbaren Texte Deutsch mit echten Umlauten; Bezeichner, Slugs und Dateinamen ASCII.
