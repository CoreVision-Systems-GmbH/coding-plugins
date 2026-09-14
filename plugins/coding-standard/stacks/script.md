# Stack-Overlay Script — natives Coding ohne Framework

Ergänzt den Kern für Skripte und kleine Werkzeuge (Bash, PowerShell, Python ohne Framework):
Wartungsläufe, Auswertungen, Umzüge, Server-Handgriffe. Kein Dienst, kein Abbild.

## 1. Zuständigkeiten & Architektur
- Ein Skript, eine Aufgabe. Wächst es über zwei Bildschirmseiten oder braucht es Zustand über
  Läufe hinweg, ist es kein Skript mehr — dann Modul oder Dienst, und der Stack wechselt.
- Ablage: ausführbare Werkzeuge in `scripts/`, Tests in `tests/`, gemeinsame Funktionen in
  `scripts/lib/`. Die bestehende Ablage des Repos hat Vorrang.
- Vor dem Code je Werkzeug festhalten: `Aufruf · Was es ändert · Was es NICHT anfasst ·
  Rückweg`. Ohne benannten Rückweg entsteht kein Werkzeug, das auf einem Server läuft.
- Sprache nach Ziel: Bash für Linux-Server, PowerShell für Windows, Python für Datenverarbeitung.

## 2. Grenzen (nicht verhandelbar)
- **Idempotent.** Zweimal aufgerufen kommt dasselbe heraus wie einmal. Was schon steht, wird
  nicht doppelt angelegt; was fehlt, wird ergänzt.
- **Kein Secret als Argument.** Kommandozeilen stehen in der Prozessliste und im Verlauf.
  Geheimnisse kommen über Umgebung, Datei mit `600` oder stdin — nie über `--token …`.
- **Kein stiller Fehlschlag.** `set -euo pipefail` in Bash, `$ErrorActionPreference = 'Stop'`
  in PowerShell, kein nacktes `except:` in Python. Ein Fehler endet mit Ausgangswert ≠ 0 und
  einer Meldung, die sagt, was zu tun ist.
- **Zerstörendes nur nach Bestätigung** oder hinter `--force`; `--dry-run` zeigt vorher, was
  passieren würde.

## 3. Werkzeugkette
- Befehle aus dem Repo ermitteln (`README`, `Makefile`). Standard für neue Werkzeuge:
  `shellcheck` für `*.sh`, `ruff format` + `ruff check` und `pytest` für `*.py`,
  `PSScriptAnalyzer` für `*.ps1`.
- CI-Reihenfolge: shellcheck → ruff → pytest → (PSScriptAnalyzer). Was im Repo nicht
  vorkommt, wird im Auftrag übersprungen, nicht rot gemeldet.
- Getestet wird, was eine Entscheidung trifft (Auswahl, Umrechnung, Parsen). Ein Aufruf, der
  nur fremde Befehle hintereinander schaltet, belegt sich mit `--dry-run`.

## 4. Betriebsvertrag
1. **Aufruf:** jedes Werkzeug versteht `--help` und beschreibt darin Aufruf, Wirkung und
   Rückweg. Lange Läufe melden Fortschritt.
2. **Konfiguration:** über Umgebung oder Argumente, nicht über bearbeitete Konstanten im
   Kopf der Datei. Geheimnisse aus dem KeePassXC-Tresor.
3. **Logging:** Ergebnis nach stdout, Meldungen und Fehler nach stderr. Damit bleibt das
   Werkzeug in einer Pipeline benutzbar. Keine Geheimnisse, keine personenbezogenen Daten.
4. **Portabilität:** Zeilenenden über `.gitattributes` (`*.sh` LF, `*.ps1`/`*.bat` CRLF).
   Keine GNU-Eigenheiten ohne Rückfallweg (`sed -i`, `timeout`, `realpath`), wenn das
   Werkzeug auch unter Windows läuft.
5. **Version:** `version.txt` im Repo, `--version` gibt sie aus. Bump über `/release`.
6. **Lieferung:** kein Abbild. Ein Tag `vX.Y.Z` erzeugt ein GitHub-Release; auf den Server
   kommt der Tarball des Tags oder ein `git checkout <tag>` — nie ein loser Stand vom
   Arbeitsplatz.
7. **Erkennung:** Der Stack hat keine Markerdatei eines Frameworks. Deshalb liegt im Repo
   `.coding-standard` mit der Zeile `stack: script` — daran erkennt der SessionStart-Hook
   dieses Overlay.

## 5. Fallen (stack-typisch)
- `set -e` greift nicht in Bedingungen, in Pipes ohne `pipefail` und nicht in Funktionen, die
  in `if` stehen. Rückgabewerte trotzdem prüfen.
- CRLF in einer `.sh` bricht die Shebang mit `bad interpreter: /bin/bash^M`.
- Unquoted `$var` mit Leerzeichen im Pfad — unter Windows der Regelfall.
- `sed -i` auf einer als Einzeldatei gemounteten Datei erreicht den Container nicht: Docker
  bindet die Inode, `sed` schreibt eine neue.
- `pkill -f muster` trifft auch die eigene SSH-Shell, in deren Kommandozeile das Muster steht.
