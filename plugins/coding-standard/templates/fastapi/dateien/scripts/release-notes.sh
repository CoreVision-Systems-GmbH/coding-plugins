#!/usr/bin/env bash
# Gibt den Abschnitt einer Fassung aus CHANGES.md auf der Standardausgabe aus.
#
#     scripts/release-notes.sh 1.0.0
#
# Gesucht wird die Überschrift "## [1.0.0]"; ausgegeben wird alles bis zur
# nächsten "## "-Überschrift. Der Release-Workflow benutzt das als Text des
# GitHub-Releases, damit die Notizen dieselben sind, die auch im Repository
# stehen — eine zweite, maschinell erzeugte Liste braucht niemand.

set -euo pipefail

cd "$(dirname "$0")/.."

if [ $# -ne 1 ]; then
    echo "Aufruf: scripts/release-notes.sh <version>   (z. B. 1.0.0)" >&2
    exit 1
fi

version="${1#v}"

if ! grep -q "^## \[${version}\]" CHANGES.md; then
    echo "Kein Abschnitt '## [${version}]' in CHANGES.md gefunden." >&2
    exit 1
fi

awk -v version="${version}" '
    $0 ~ "^## \\[" version "\\]" { found = 1; next }
    found && /^## / { exit }
    found { print }
' CHANGES.md
