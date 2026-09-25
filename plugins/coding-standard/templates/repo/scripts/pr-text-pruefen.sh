#!/usr/bin/env bash
# pr-text-pruefen.sh — prüft den PR-Text gegen die Vorlage: Der PR ist die Lieferung, und ein
# PR ohne Abnahmekriterien, ohne belegten Prüfweg, ohne „Nicht geprüft“ und ohne Rückweg ist
# nicht reviewbar. Eine Textregel wird damit ein Tor.
#
# Aufruf:   gh pr view <nr> --json body -q .body | bash scripts/pr-text-pruefen.sh
#           bash scripts/pr-text-pruefen.sh <datei-mit-pr-text>
# Ändert:   nichts. Exit 0 = vollständig, Exit 1 = Lücken (je eine Zeile FEHLT), Exit 2 = leer.
# Rückweg:  keiner nötig.
#
# Geprüft wird: eine Zeile in der Tabelle „Abnahmekriterien“ mit Nr., Kriterium und Nachweis;
# eine Zeile im „Prüfweg“ mit Befehl und Ergebnis; Text hinter „Nicht geprüft:“ und hinter
# „Rückweg (Rollback):“. HTML-Kommentare der Vorlage zählen nicht als Inhalt.
# In der CI läuft das im Auftrag `ci` (Schritt „PR-Text prüfen“); Dependabot ist ausgenommen.

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

if [ $# -ge 1 ]; then
    text="$(cat "$1")"
else
    text="$(cat)"
fi
text="${text//$'\r'/}"

# HTML-Kommentare entfernen — auch über mehrere Zeilen; sie sind Hilfetext der Vorlage.
strip_kommentare() {
    awk '
        BEGIN { c = 0 }
        {
            line = $0; out = ""
            while (length(line)) {
                if (!c) {
                    i = index(line, "<!--")
                    if (!i) { out = out line; break }
                    out = out substr(line, 1, i - 1); line = substr(line, i + 4); c = 1
                } else {
                    j = index(line, "-->")
                    if (!j) { line = ""; break }
                    line = substr(line, j + 3); c = 0
                }
            }
            print out
        }'
}
text="$(printf '%s\n' "$text" | strip_kommentare)"

if [ -z "${text//[[:space:]]/}" ]; then
    echo "FEHLT: Der PR-Text ist leer — Vorlage .github/pull_request_template.md füllen." >&2
    exit 2
fi

fehler=0
fehlt() { printf 'FEHLT: %s\n' "$1" >&2; fehler=1; }

# tabelle_nach <markierung> — Tabellenzeilen ab der Zeile, die die Markierung enthält, bis zur
# nächsten Überschrift (`# …`). Die Trennlinie (nur |, -, :, Leerraum — auch mit
# Ausrichtungs-Doppelpunkten) und die Kopfzeile unmittelbar davor fallen weg, egal wie die
# Kopfzeile heißt. Die Zwischenzeile „**Automatisiert**“ der Vorlage darf fehlen.
tabelle_nach() {
    printf '%s\n' "$text" | awk -v m="$1" '
        f && /^# / { exit }
        index($0, m) { f = 1; next }
        f && /^\|/ { z[++n] = $0 }
        END {
            for (i = 1; i <= n; i++) if (z[i] ~ /^[|:\t -]+$/) { weg[i] = 1; weg[i - 1] = 1 }
            for (i = 1; i <= n; i++) if (!weg[i]) print z[i]
        }'
}

# gefuellte_zeilen <mindestzahl gefüllter Zellen> — zählt Tabellenzeilen von stdin, in denen
# mindestens so viele Zellen Inhalt haben. Ein fehlendes schließendes | ist erlaubt (GitHub
# rendert die Zeile trotzdem).
gefuellte_zeilen() {
    awk -v min="$1" '
        { z0 = $0; sub(/^[ \t]*\|/, "", z0); sub(/\|[ \t]*$/, "", z0)
          k = split(z0, zellen, "|"); n = 0
          for (i = 1; i <= k; i++) { z = zellen[i]; gsub(/^[ \t]+|[ \t]+$/, "", z); if (z != "") n++ }
          if (n >= min) c++ }
        END { print c + 0 }'
}

# feld <markierung> — Text hinter „**Markierung**“ am Zeilenanfang (auch als Listenpunkt
# „- **…**“) auf derselben Zeile und den folgenden; eine Leerzeile direkt danach ist erlaubt
# (eigener Absatz), die zweite beendet das Feld, ebenso die nächste Fettmarkierung oder
# Überschrift. Ohne Leerraum. Eine Markierung mitten in einem Satz zählt nicht.
feld() {
    printf '%s\n' "$text" | awk -v l="$1" '
        f && (/^\*\*/ || /^#/ || /^- \*\*/) { exit }
        f && /^[ \t]*$/ { if (leer++) exit; next }
        !f { z = $0; sub(/^- /, "", z); if (substr(z, 1, length(l)) == l) { f = 1; $0 = substr(z, length(l) + 1) } }
        f { printf "%s", $0 }' | tr -d '[:space:]'
}

anzahl="$(tabelle_nach '**Abnahmekriterien' | gefuellte_zeilen 3)"
[ "$anzahl" -ge 1 ] || fehlt "Abnahmekriterien: keine Zeile mit Nr. (A1…), Kriterium und Nachweis."

anzahl="$(tabelle_nach '# Prüfweg' | gefuellte_zeilen 2)"
[ "$anzahl" -ge 1 ] || fehlt "Prüfweg: keine Zeile mit Befehl und Ergebnis — nur eintragen, was wirklich gelaufen ist."

# Keine typografischen Anführungszeichen in doppelt zitierten Zeichenketten: shellcheck
# meldet sie als SC1111 (Warnung), und der Prüfbefehl neuer Projekte läuft auf Warnstufe.
[ -n "$(feld '**Nicht geprüft:**')" ] || fehlt 'Feld „Nicht geprüft:“ ist leer — was nicht geprüft wurde, wird benannt (notfalls „nichts“ mit Begründung).'

[ -n "$(feld '**Rückweg (Rollback):**')" ] || fehlt 'Feld „Rückweg (Rollback):“ ist leer — wie kommt man zurück, wenn es schiefgeht?'

if [ "$fehler" -ne 0 ]; then
    echo "PR-Text unvollständig — Vorlage .github/pull_request_template.md füllen (Abnahmekriterien, Prüfweg, Nicht geprüft, Rückweg)." >&2
    exit 1
fi
echo "PR-Text vollständig: Abnahmekriterien, Prüfweg, Nicht geprüft, Rückweg."
