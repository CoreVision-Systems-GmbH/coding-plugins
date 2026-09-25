#!/usr/bin/env bash
# test-pr-text.sh — prüft templates/repo/scripts/pr-text-pruefen.sh mit Beispieltexten.
#
# Aufruf:   bash plugins/coding-standard/scripts/test-pr-text.sh
# Ergebnis: Exit 0, wenn alle Fälle grün sind, sonst Exit 1.
#
# Geprüft werden: die unveränderte Vorlage (rot, alle vier Lücken), ein vollständiger Text
# (grün), je eine Lücke einzeln (rot mit der passenden Meldung), Kommentare der Vorlage als
# Nicht-Inhalt, leerer Text (Exit 2), Aufruf mit Datei statt stdin, --help.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRUEFER="$HERE/../templates/repo/scripts/pr-text-pruefen.sh"
VORLAGE="$HERE/../templates/repo/.github/pull_request_template.md"

fehler=0
ok() { echo "ok     $1"; }
nichtok() { echo "FEHLER $1"; fehler=$((fehler + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# lauf <erwarteter exit> <name> <text>
lauf() {
    local erwartet="$1" name="$2" text="$3" ausgabe status
    ausgabe="$(printf '%s\n' "$text" | bash "$PRUEFER" 2>&1)" && status=0 || status=$?
    AUSGABE="$ausgabe"
    if [ "$status" -eq "$erwartet" ]; then ok "$name (Exit $status)"; else nichtok "$name (Exit $status statt $erwartet): $ausgabe"; fi
}
meldet() { # <name> <muster> — die letzte Ausgabe enthält das Muster
    if printf '%s' "$AUSGABE" | grep -q -- "$2"; then ok "$1"; else nichtok "$1 — Ausgabe: $AUSGABE"; fi
}
meldet_nicht() {
    if printf '%s' "$AUSGABE" | grep -q -- "$2"; then nichtok "$1 — Ausgabe: $AUSGABE"; else ok "$1"; fi
}

voll="$(cat <<'EOF'
# Was und Warum

**Was:** Der Guard blockt mehr.

**Abnahmekriterien** — nummeriert, je mit Nachweis:

| Nr. | Kriterium | Nachweis |
|---|---|---|
| A1 | `git add .` wird geblockt, `git add <datei>` nicht | Fälle 50–56 |

**Warum:** Fehlermuster F und H.

**Nicht Teil davon:** gitleaks.

# Prüfweg

**Automatisiert** — nur Befehle eintragen, die tatsächlich gelaufen sind, mit Ergebnis:

| Befehl | Ergebnis |
|---|---|
| `bash hooks/test-git-guard.sh` | 120 Fälle, 0 Fehler |

**Manuell** — der Klickweg:

1. `git add .` tippen → Ablehnung.

**Nicht geprüft:** Wirkung in einer laufenden Session.

# Risiko

- **Auswirkung:** Sessions müssen Dateien benennen.
- **Rückweg (Rollback):** Revert; 0.10.0 bleibt im Verteil-Repo.

# Definition of Done

- [x] CI grün
EOF
)"

echo "== Vorlage und vollständiger Text"
lauf 1 "unveränderte Vorlage ist rot" "$(cat "$VORLAGE")"
meldet "Vorlage: Abnahmekriterien fehlen" "Abnahmekriterien"
meldet "Vorlage: Prüfweg fehlt" "Prüfweg"
meldet "Vorlage: Nicht geprüft fehlt" "Nicht geprüft"
meldet "Vorlage: Rückweg fehlt" "Rückweg"
lauf 0 "vollständiger Text ist grün" "$voll"
meldet "grün meldet Vollständigkeit" "vollständig"

echo
echo "== Je eine Lücke"
lauf 1 "Abnahmekriterien nur mit Nr." "$(printf '%s\n' "$voll" | sed 's/^| A1 | .*$/| A1 |  |  |/')"
meldet "meldet Abnahmekriterien" "Abnahmekriterien"
meldet_nicht "meldet nicht den Prüfweg" "Prüfweg:"
lauf 1 "Prüfweg ohne Ergebnis" "$(printf '%s\n' "$voll" | sed 's/^| `bash hooks.*$/| `bash hooks\/test-git-guard.sh` |  |/')"
meldet "meldet Prüfweg" "Prüfweg"
lauf 1 "Nicht geprüft leer" "$(printf '%s\n' "$voll" | sed 's/^\*\*Nicht geprüft:\*\* .*$/**Nicht geprüft:**/')"
meldet "meldet Nicht geprüft" "Nicht geprüft"
lauf 1 "Rückweg leer" "$(printf '%s\n' "$voll" | sed 's/^- \*\*Rückweg (Rollback):\*\* .*$/- **Rückweg (Rollback):**/')"
meldet "meldet Rückweg" "Rückweg"

echo
echo "== Tabellenformen und Markierungen"
lauf 0 "Zeile ohne schließendes | zählt" "$(printf '%s\n' "$voll" | sed 's/| Fälle 50–56 |$/| Fälle 50–56/')"
lauf 0 "Abnahmekriterien mit Doppelpunkt statt Gedankenstrich" "$(printf '%s\n' "$voll" | sed 's/^\*\*Abnahmekriterien\*\* — nummeriert, je mit Nachweis:$/**Abnahmekriterien:**/')"
lauf 1 "Trennlinie mit Ausrichtung und leere Zeile bleiben rot" "$(printf '%s\n' "$voll" | sed '0,/^|---|---|---|$/s//|:--|:--|:--|/; s/^| A1 | .*$/| A1 |  |  |/')"
meldet "meldet Abnahmekriterien trotz :-- Trennlinie" "Abnahmekriterien"
lauf 1 "eigene Kopfzeile zählt nicht als Inhalt" "$(printf '%s\n' "$voll" | sed 's/^| Nr\. | Kriterium | Nachweis |$/| Schritt | Was | Beleg |/; s/^| A1 | .*$/| A1 |  |  |/')"
meldet "meldet Abnahmekriterien trotz eigener Kopfzeile" "Abnahmekriterien"
lauf 1 "Markierung mitten im Satz zählt nicht" "$(printf '%s\n' "$voll" | sed 's/^\*\*Was:\*\* Der Guard blockt mehr\.$/**Was:** Der Guard blockt mehr; Text hinter **Nicht geprüft:** ist Pflicht./; s/^\*\*Nicht geprüft:\*\* .*$/**Nicht geprüft:**/')"
meldet "meldet Nicht geprüft trotz Markierung im Satz" "Nicht geprüft"
lauf 0 "Absatz nach einer Leerzeile zählt" "$(printf '%s\n' "$voll" | sed 's/^\*\*Nicht geprüft:\*\* .*$/**Nicht geprüft:**\n\nDie Wirkung in einer Session./')"

echo
echo "== Kommentare, Folgezeilen, leerer Text, Datei, --help"
lauf 1 "Kommentar der Vorlage zählt nicht als Inhalt" "$(printf '%s\n' "$voll" | sed 's/^\*\*Nicht geprüft:\*\* .*$/**Nicht geprüft:**\n<!-- Ehrlich benennen. -->/')"
meldet "meldet Nicht geprüft trotz Kommentar" "Nicht geprüft"
lauf 0 "Text auf der Folgezeile zählt" "$(printf '%s\n' "$voll" | sed 's/^\*\*Nicht geprüft:\*\* .*$/**Nicht geprüft:**\nDie Wirkung in einer Session./')"
lauf 0 "mehrzeiliger Kommentar vor echtem Inhalt" "$(printf '%s\n' "$voll" | sed 's/^\*\*Was:\*\* .*$/**Was:** <!-- ein\nmehrzeiliger\nKommentar --> Der Guard./')"
lauf 2 "leerer Text: Exit 2" ""
meldet "leer: Meldung" "leer"
printf '%s\n' "$voll" > "$tmp/pr.md"
if bash "$PRUEFER" "$tmp/pr.md" >/dev/null 2>&1; then ok "Aufruf mit Datei"; else nichtok "Aufruf mit Datei"; fi
if bash "$PRUEFER" --help | grep -q 'Aufruf:'; then ok "--help nennt den Aufruf"; else nichtok "--help nennt den Aufruf"; fi

echo
if [ "$fehler" -eq 0 ]; then echo "Alle Fälle grün."; else echo "Fehler: $fehler"; exit 1; fi
