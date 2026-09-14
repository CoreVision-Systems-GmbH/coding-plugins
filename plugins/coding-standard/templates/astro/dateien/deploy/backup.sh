#!/usr/bin/env bash
# Sicherung — bewusst leer.
#
#     deploy/backup.sh
#
# Die Site hat keine Daten: kein Volume, keine Datenbank, keine Uploads.
# Alles, was läuft, steckt im Abbild und kommt aus einem Tag in GHCR. Der
# Rückweg ist deshalb keine Sicherung, sondern `deploy/update.sh <alter tag>`.
#
# Das Skript gibt es trotzdem, damit Aufrufer, die vor jeder Aktualisierung
# `deploy/backup.sh` erwarten (Instanzordner im deployments-Repo), nicht an
# einer fehlenden Datei scheitern. Es endet mit 0.

set -euo pipefail

echo "Keine Daten: {{NAME}} hat kein Volume und keine Datenbank — nichts zu sichern."
echo "Rückweg bei Bedarf: deploy/update.sh <alter tag>"
exit 0
