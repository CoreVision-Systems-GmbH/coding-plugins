#!/usr/bin/env bash
# lizenzen-pruefen.sh — Lizenzen der ausgelieferten Abhängigkeiten gegen eine Allow-Liste:
# Copyleft (GPL, AGPL) in nicht offen verteilter Software ist ein Befund, schwaches Copyleft
# (LGPL, MPL) und Unbekanntes eine Warnung. Ausnahmen mit Grund in docs/lizenzen-ausnahmen.txt
# (ein Paketname je Zeile, dahinter # und der Grund) — dieselbe Idee wie .gitleaks.toml.
#
# Aufruf:   bash scripts/lizenzen-pruefen.sh     — Teil von `check` und des CI-Schritts „Lizenzen“
# Ändert:   nichts. Exit 0 = sauber (Warnungen erlaubt), Exit 1 = Befunde.
# Rückweg:  keiner nötig.
#
# Quellen, je nachdem, was im Repo liegt: composer (vendor/, `composer licenses --no-dev`), npm
# (node_modules/, nur Laufzeit-Abhängigkeiten: `npm ls --omit=dev`), pip (.venv oder das aktive
# Python — die ganze Umgebung, also auch Entwicklungswerkzeuge). Eine WordPress-Site (wp-cli.yml)
# darf GPL: WordPress und seine Plugins sind GPL, und die Site wird nicht weitergegeben.
# Lizenzausdrücke: bei „MIT OR Apache-2.0“ genügt ein erlaubter Bestandteil, bei „MIT AND
# LGPL-3.0“ müssen alle erlaubt sein; Mischformen gelten wie OR.

set -euo pipefail
cd "$(dirname "$0")/.."

ERLAUBT='MIT|MIT-0|MIT-CMU|HPND|BSD-2-Clause|BSD-2-Clause-Patent|BSD-3-Clause|BSD|Apache-2.0|Apache-2|ISC|0BSD|Unlicense|PublicDomain|CC0-1.0|CC-BY-4.0|CC-BY-3.0|Python-2.0|Python-2.0.1|PSF-2.0|PSF|Zlib|BlueOak-1.0.0|WTFPL|Artistic-2.0|BSL-1.0|OFL-1.1|MPL-2.0|LGPL-2.1|LGPL-2.1-only|LGPL-2.1-or-later|LGPL-3.0|LGPL-3.0-only|LGPL-3.0-or-later|LGPL-2.0-or-later'
WARNUNG='MPL-2.0|LGPL-2.1|LGPL-2.1-only|LGPL-2.1-or-later|LGPL-3.0|LGPL-3.0-only|LGPL-3.0-or-later|LGPL-2.0-or-later'
[ -f wp-cli.yml ] && ERLAUBT="$ERLAUBT|GPL-2.0|GPL-2.0-only|GPL-2.0-or-later|GPL-2.0+|GPL-3.0|GPL-3.0-only|GPL-3.0-or-later|GPL-3.0+|GPLv2|GPLv3|GPLv2+|GPLv3+"
ausnahmen="docs/lizenzen-ausnahmen.txt"

befunde=0
warnungen=0
gezaehlt=0

# pruefe <quelle> <paket> <lizenz>
pruefe() {
    local quelle="$1" paket="$2" lizenz="$3"
    local teile=() teil erlaubt=0 gesamt=0 stark=0 schwach="" hat_and=0 hat_or=0 nach_with=0 noetig=1
    # Unter Windows liefern Python und Node Zeilen mit \r — das macht aus „MIT“ ein „MIT\r“.
    paket="${paket//$'\r'/}"
    lizenz="${lizenz//$'\r'/}"
    lizenz="${lizenz//Public Domain/PublicDomain}"
    lizenz="${lizenz//Public_Domain/PublicDomain}"
    gezaehlt=$((gezaehlt + 1))
    # pip-Namen sind nicht schreibungsempfindlich (Jinja2 = jinja2), daher -i.
    if [ -f "$ausnahmen" ] && grep -qiE "^[[:space:]]*$(printf '%s' "$paket" | sed 's/[][\.*^$/]/\\&/g')([[:space:]]|#|$)" "$ausnahmen"; then
        return 0
    fi
    # Die Quellen liefern Ausdrücke ohne Leerzeichen („Apache-2.0_OR_BSD-2-Clause“) — erst in
    # Bestandteile zerlegen; read -ra statt Wortaufteilung, damit „MIT*“ nicht als Glob wirkt.
    read -ra teile <<< "$(printf '%s' "$lizenz" | tr '(),/_' '     ')"
    for teil in "${teile[@]}"; do
        # Die Ausnahme hinter WITH („GPL-2.0 WITH Classpath-exception-2.0“) ist keine Lizenz.
        if [ "$nach_with" = 1 ]; then nach_with=0; continue; fi
        case "$teil" in AND) hat_and=1; continue ;; OR) hat_or=1; continue ;; WITH) nach_with=1; continue ;; '') continue ;; esac
        gesamt=$((gesamt + 1))
        if printf '%s' "$teil" | grep -qE "^($ERLAUBT)$"; then
            erlaubt=$((erlaubt + 1))
            if printf '%s' "$teil" | grep -qE "^($WARNUNG)$"; then schwach="$teil"; else stark=1; fi
        fi
    done
    # AND ohne OR: alle Bestandteile müssen erlaubt sein — „GPL-3.0 AND MIT“ bindet trotz MIT.
    # Sonst (OR, Mischformen) genügt ein erlaubter Bestandteil.
    if [ "$hat_and" = 1 ] && [ "$hat_or" = 0 ]; then noetig=$gesamt; fi
    if [ "$gesamt" -gt 0 ] && [ "$erlaubt" -ge "$noetig" ]; then
        # Schwaches Copyleft nur melden, wenn kein permissiver OR-Zweig es ersetzt.
        if [ -n "$schwach" ] && { [ "$noetig" -gt 1 ] || [ "$stark" -eq 0 ]; }; then
            printf 'WARN    %-9s %-48s %s — schwaches Copyleft: Weitergabe und Änderungen prüfen\n' "$quelle" "$paket" "$schwach"
            warnungen=$((warnungen + 1))
        fi
        return 0
    fi
    case "$lizenz" in
        ''|UNKNOWN|unknown|SEE*|LicenseRef*|Other*|Proprietary*|proprietary|MIT\*|BSD\*|Apache\*)
            printf 'WARN    %-9s %-48s %s — Lizenz unklar, von Hand prüfen\n' "$quelle" "$paket" "${lizenz:-unbekannt}"
            warnungen=$((warnungen + 1)); return 0 ;;
    esac
    printf 'BEFUND  %-9s %-48s %s — nicht auf der Allow-Liste (Copyleft?); Ausnahme mit Grund in %s\n' "$quelle" "$paket" "$lizenz" "$ausnahmen"
    befunde=$((befunde + 1))
}

# --- composer: nur require, nicht require-dev — ausgeliefert wird ohne Entwicklungswerkzeuge.
# Ohne composer im PATH nimmt das Skript Herds composer.phar, wie das Gerüst beim Bau.
composer_lauf() {
    if command -v composer >/dev/null 2>&1; then composer "$@"
    else php "$HOME/.config/herd/bin/composer.phar" "$@"; fi
}
if [ -f composer.json ] && [ -d vendor ] && { command -v composer >/dev/null 2>&1 || [ -f "$HOME/.config/herd/bin/composer.phar" ]; }; then
    while read -r paket lizenz; do
        [ -n "$paket" ] && pruefe composer "$paket" "$lizenz"
    done < <(composer_lauf licenses --no-dev --format=json 2>/dev/null | php -r '
        $d = json_decode(stream_get_contents(STDIN), true);
        foreach (($d["dependencies"] ?? []) as $n => $p) {
            echo $n, " ", implode("/", (array) ($p["license"] ?? ["UNKNOWN"])) ?: "UNKNOWN", "\n";
        }')
fi

# --- npm (nur Laufzeit-Abhängigkeiten)
if [ -f package.json ] && [ -d node_modules ] && command -v node >/dev/null 2>&1; then
    while read -r paket lizenz; do
        [ -n "$paket" ] && pruefe npm "$paket" "$lizenz"
    done < <(npm ls --omit=dev --all --parseable 2>/dev/null | node -e '
        const fs = require("fs"), p = require("path");
        const seen = new Set();
        for (const pfad of fs.readFileSync(0, "utf8").split("\n")) {
            if (!pfad || !pfad.includes("node_modules")) continue;
            const pj = p.join(pfad, "package.json");
            if (!fs.existsSync(pj)) continue;
            let j; try { j = JSON.parse(fs.readFileSync(pj, "utf8")); } catch { continue; }
            if (!j.name || seen.has(j.name)) continue;
            seen.add(j.name);
            let l = j.license ?? (Array.isArray(j.licenses) ? j.licenses.map(x => x.type ?? x).join(" OR ") : "UNKNOWN");
            if (typeof l === "object" && l) l = l.type ?? "UNKNOWN";
            // Leerraum nur bündeln, nicht löschen — sonst wird aus „MIT OR GPL-2.0“ ein Wort.
            console.log(j.name + " " + String(l).replace(/\s+/g, " "));
        }')
fi

# --- pip
if [ -f requirements.txt ] || [ -f pyproject.toml ]; then
    if [ -x .venv/Scripts/python.exe ]; then py=".venv/Scripts/python.exe"
    elif [ -x .venv/bin/python ]; then py=".venv/bin/python"
    else py="$(command -v python || command -v python3 || true)"; fi
    if [ -n "$py" ] && ! printf '%s' "$py" | grep -q WindowsApps; then
        while read -r paket lizenz; do
            [ -n "$paket" ] && pruefe pip "$paket" "$lizenz"
        done < <("$py" - <<'PYEOF'
import importlib.metadata as m
# Klassifikatoren und Freitext auf SPDX-Kurzformen abbilden — die Allow-Liste kennt nur diese.
ABBILDUNG = {
    "MIT License": "MIT", "MIT": "MIT", "BSD License": "BSD-3-Clause", "BSD": "BSD-3-Clause",
    "Apache Software License": "Apache-2.0", "Apache 2.0": "Apache-2.0", "Apache-2.0": "Apache-2.0",
    "Apache License 2.0": "Apache-2.0", "Apache License, Version 2.0": "Apache-2.0",
    "ISC License (ISCL)": "ISC", "ISC": "ISC", "Python Software Foundation License": "PSF-2.0",
    "Mozilla Public License 2.0 (MPL 2.0)": "MPL-2.0", "MPL-2.0": "MPL-2.0",
    "GNU Lesser General Public License v2 or later (LGPLv2+)": "LGPL-2.1-or-later",
    "GNU Lesser General Public License v3 (LGPLv3)": "LGPL-3.0", "GNU Library or Lesser General Public License (LGPL)": "LGPL-3.0",
    "GNU General Public License v2 (GPLv2)": "GPL-2.0", "GNU General Public License v3 (GPLv3)": "GPL-3.0",
    "GNU General Public License v2 or later (GPLv2+)": "GPL-2.0-or-later", "GNU General Public License v3 or later (GPLv3+)": "GPL-3.0-or-later",
    "GNU Affero General Public License v3": "AGPL-3.0", "The Unlicense (Unlicense)": "Unlicense", "Zope Public License": "ZPL-2.1",
    "Public Domain": "Unlicense", "CC0 1.0 Universal (CC0 1.0) Public Domain Dedication": "CC0-1.0",
}
for d in m.distributions():
    name = d.metadata.get("Name") or ""
    lic = (d.metadata.get("License-Expression") or "").strip()
    if not lic:
        cls = [c.split("::")[-1].strip() for c in (d.metadata.get_all("Classifier") or []) if c.startswith("License ::")]
        cls = [c for c in cls if c != "OSI Approved"]
        if cls:
            lic = " OR ".join(ABBILDUNG.get(c, c) for c in cls)
        else:
            lic = (d.metadata.get("License") or "").strip().splitlines()[0][:80] if d.metadata.get("License") else ""
            lic = ABBILDUNG.get(lic, lic)
    print(name, lic.replace(" ", "_") or "UNKNOWN")
PYEOF
)
    fi
fi

if [ "$gezaehlt" -eq 0 ]; then
    echo "Lizenzen: keine installierten Abhängigkeiten gefunden (vendor/, node_modules/, .venv) — nichts geprüft." >&2
    exit 0
fi
if [ "$befunde" -ne 0 ]; then
    printf 'Lizenzen: %s Befund(e), %s Warnung(en) bei %s Paketen.\n' "$befunde" "$warnungen" "$gezaehlt" >&2
    exit 1
fi
printf 'Lizenzen: %s Pakete geprüft, %s Warnung(en), keine Befunde.\n' "$gezaehlt" "$warnungen"
