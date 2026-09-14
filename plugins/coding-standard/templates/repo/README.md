# {{NAME}}

{{PURPOSE}}

- **Stack:** {{STACK_LABEL}}
- **Repository:** `{{OWNER}}/{{NAME}}` (privat)
- **Kunde/Instanz:** {{CUSTOMER}}
- **Angelegt:** {{DATE}} nach Firmenstandard (`coding-standard@corevision`)

## Einrichtung

<!-- Die Befehle stehen in CLAUDE.md unter „Befehle". Hier steht, was ein Mensch tun muss,
     der das Repo zum ersten Mal auscheckt — einschließlich der Dinge, die kein Befehl
     erledigt (Zugangsdaten, Systemvoraussetzungen). -->

1. Repository klonen.
2. Abhängigkeiten installieren und Prüfungen laufen lassen (siehe `CLAUDE.md`).
3. `.env` aus `.env.example` ableiten, falls das Projekt eine braucht. Die Werte kommen aus
   dem KeePassXC-Tresor, nie aus dem Repository.

## Betrieb

<!-- Wo läuft es, unter welcher Adresse, auf welchem Server, mit welchem Ausrollweg?
     Solange nichts läuft, bleibt hier „noch nicht ausgerollt" stehen. -->

Noch nicht ausgerollt.

## Konfiguration

<!-- Jeder Schlüssel aus .env.example mit einem Satz: wofür, welche Werte, was passiert,
     wenn er fehlt. Secrets stehen hier nur mit Namen, nie mit Wert. -->

Siehe `.env.example` — dort ist jeder Schlüssel kommentiert.

## Update

<!-- Wie kommt eine neue Fassung auf den Server, und wie kommt man zurück? -->

Neue Fassung entsteht aus einem Tag `vX.Y.Z` (`/release`). Der Rückweg ist derselbe Weg mit
dem vorigen Tag.

## Lizenz

Proprietär, {{COMPANY}}. Siehe `LICENSE`.
