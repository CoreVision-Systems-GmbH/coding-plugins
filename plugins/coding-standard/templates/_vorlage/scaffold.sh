#!/usr/bin/env bash
# Gerüst für den Stack <name>.
#
# Die Datei ist optional: Bringt der Stack keinen Installer mit und kommt alles
# aus `dateien/`, kann sie entfallen — dann legt der Bootstrap den Zielordner
# selbst an.
#
# Aufgerufen wird sie zweimal, mit unterschiedlichem PHASE:
#
#   PHASE=geruest     vor dem Kopieren der Vorlagen. Der Zielordner ist leer
#                     oder fehlt noch. Hier läuft der Installer des Frameworks
#                     (`laravel new`, `npx create-…`) — viele Installer
#                     verweigern die Arbeit in einem nicht leeren Ordner.
#
#   PHASE=einrichten  nach dem Kopieren. Alle Vorlagen liegen bereits im
#                     Zielordner. Hier läuft die Einrichtung (Abhängigkeiten,
#                     virtuelle Umgebung) und die erste Prüfung. Was hier rot
#                     ist, wird nicht ausgeliefert.
#
# Umgebung (alle gesetzt):
#   NAME        Projektname in kebab-case, z. B. kunde-werkzeug
#   DIR         absoluter Pfad des Zielordners
#   OWNER       GitHub-Eigentümer, z. B. CoreVision-Systems-GmbH
#   IMAGE       ghcr.io/<owner klein>/<name>
#   PURPOSE     Zweck in ein bis zwei Sätzen
#   ENV_PREFIX  Präfix für Umgebungsvariablen, z. B. WERKZEUG_
#   PHASE       geruest | einrichten
#
# Bricht das Skript ab, bricht der ganze Lauf ab — der Zielordner bleibt zur
# Ansicht stehen. Deshalb: nur abbrechen, wenn das Gerüst wirklich unbrauchbar
# ist. Alles, was von Hand nachgeholt werden kann, gehört als Zeile nach
# "$DIR/.projekt-neu-nacharbeit" und wird im Abschlussbericht ausgegeben.

set -euo pipefail

meldung() { printf '   %s\n' "$1"; }
abbruch() { printf '\nFEHLER: %s\n' "$1" >&2; exit 1; }

if [ "$PHASE" = "geruest" ]; then
    mkdir -p "$DIR"
    # <hier der Installer des Frameworks>
    exit 0
fi

cd "$DIR"

# <hier Abhängigkeiten installieren und einmal alle Prüfungen laufen lassen>

meldung "Gerüst steht."
