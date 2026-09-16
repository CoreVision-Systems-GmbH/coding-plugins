#!/usr/bin/env bash
# Prüft standard-context.sh gegen Wegwerf-Projekte: Aktivierung, Stack-Erkennung, Größe, Notausgang.
set -u
hier="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$hier/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fehler=0
lauf() { # <projektdir> [env]  → Ausgabe des Hooks
    (cd "$1" && env CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$1" ${2:-} bash "$hier/standard-context.sh")
}
pruefe() { # <name> <projektdir> <erwartung> [env]
    local name="$1" dir="$2" erwartung="$3" out
    out="$(lauf "$dir" "${4:-}")"
    case "$erwartung" in
        leer)    [ -z "$out" ] ;;
        kern)    grep -q 'Stack erkannt: keiner' <<<"$out" && grep -q 'core/kern.md' <<<"$out" && ! grep -q 'stacks/' <<<"$out" ;;
        laravel) grep -q 'Stack erkannt: laravel)' <<<"$out" && grep -q 'stacks/laravel.md' <<<"$out" && ! grep -q 'stacks/fastapi.md' <<<"$out" ;;
        fastapi) grep -q 'Stack erkannt: fastapi)' <<<"$out" && grep -q 'stacks/fastapi.md' <<<"$out" && ! grep -q 'stacks/laravel.md' <<<"$out" ;;
        beide)   grep -q 'Stack erkannt: laravel fastapi' <<<"$out" && grep -q 'stacks/laravel.md' <<<"$out" && grep -q 'stacks/fastapi.md' <<<"$out" ;;
        nextjs)  grep -q 'Stack erkannt: nextjs)' <<<"$out" && grep -q 'stacks/nextjs.md' <<<"$out" && ! grep -q 'kein Overlay' <<<"$out" && ! grep -q 'stacks/astro.md' <<<"$out" ;;
        astro)   grep -q 'Stack erkannt: astro)' <<<"$out" && grep -q 'stacks/astro.md' <<<"$out" && ! grep -q 'stacks/laravel.md' <<<"$out" ;;
        wordpress) grep -q 'Stack erkannt: wordpress)' <<<"$out" && grep -q 'stacks/wordpress.md' <<<"$out" && ! grep -q 'stacks/laravel.md' <<<"$out" ;;
        script)  grep -q 'Stack erkannt: script)' <<<"$out" && grep -q 'stacks/script.md' <<<"$out" ;;
        marker2) grep -q 'Stack erkannt: laravel script' <<<"$out" && grep -q 'stacks/laravel.md' <<<"$out" && grep -q 'stacks/script.md' <<<"$out" ;;
    esac
    if [ $? -eq 0 ]; then echo "ok    $name"; else echo "FEHLER $name (erwartet: $erwartung)"; echo "$out" | head -5 | sed 's/^/      | /'; fehler=$((fehler+1)); fi
}
aktiviert() { mkdir -p "$1/.claude"; echo '{"enabledPlugins":{"coding-standard@corevision":true}}' > "$1/.claude/settings.json"; }

d="$tmp/nicht-aktiviert"; mkdir -p "$d"; echo '{"require":{"laravel/framework":"^13"}}' > "$d/composer.json"
pruefe "ohne Erklärung keine Ausgabe" "$d" leer

d="$tmp/marker"; mkdir -p "$d"; touch "$d/.coding-standard"
pruefe "Markerdatei aktiviert Kern" "$d" kern

d="$tmp/doku"; aktiviert "$d"
pruefe "aktiviert ohne Stack: nur Kern" "$d" kern

d="$tmp/laravel"; aktiviert "$d"; echo '{"require":{"php":"^8.4","laravel/framework":"^13.0"}}' > "$d/composer.json"
pruefe "Laravel erkannt" "$d" laravel

d="$tmp/fastapi-req"; aktiviert "$d"; printf 'fastapi==0.115.6\nuvicorn[standard]==0.34.0\n' > "$d/requirements.txt"
pruefe "FastAPI über requirements.txt" "$d" fastapi

d="$tmp/fastapi-pyproject"; aktiviert "$d"; printf '[project]\ndependencies = ["fastapi>=0.115"]\n' > "$d/pyproject.toml"
pruefe "FastAPI über pyproject.toml" "$d" fastapi

d="$tmp/kein-fastapi"; aktiviert "$d"; printf 'requests==2.32.0\n' > "$d/requirements.txt"
pruefe "Python ohne FastAPI: nur Kern" "$d" kern

d="$tmp/beide"; aktiviert "$d"; echo '{"require":{"laravel/framework":"^13"}}' > "$d/composer.json"; printf 'fastapi==0.115.6\n' > "$d/requirements.txt"
pruefe "zwei Stacks zugleich" "$d" beide

d="$tmp/nextjs"; aktiviert "$d"; echo '{"dependencies":{"next":"15.0.0","react":"19"}}' > "$d/package.json"
pruefe "Next.js erkannt, Ausnahme-Overlay geladen" "$d" nextjs

d="$tmp/astro"; aktiviert "$d"; echo '{"dependencies":{"astro":"^6.0.0"}}' > "$d/package.json"
pruefe "Astro erkannt" "$d" astro

d="$tmp/wordpress-bedrock"; aktiviert "$d"; echo '{"require":{"roots/wordpress":"~7.1.0","roots/wp-config":"^1.0"}}' > "$d/composer.json"
pruefe "WordPress erkannt (Bedrock, composer.json)" "$d" wordpress

d="$tmp/wordpress-bestand"; aktiviert "$d"; printf '<?php\ndefine("DB_NAME", "bestand");\n' > "$d/wp-config.php"
pruefe "WordPress erkannt (Bestand, wp-config.php)" "$d" wordpress

d="$tmp/marker-script"; mkdir -p "$d"; printf 'stack: script\n' > "$d/.coding-standard"
pruefe "Markerdatei nennt den Stack (script)" "$d" script

d="$tmp/marker-dazu"; aktiviert "$d"; echo '{"require":{"laravel/framework":"^13"}}' > "$d/composer.json"
printf 'stack: script\nstack: laravel\n' > "$d/.coding-standard"
pruefe "Marker ergänzt, doppelter Stack nur einmal" "$d" marker2

d="$tmp/aus"; aktiviert "$d"
pruefe "Notausgang CODING_STANDARD_OFF=1" "$d" leer "CODING_STANDARD_OFF=1"

# --stacks: Erkennung ohne Erklärung, nur die Namen (für projekt-aufnehmen.sh).
d="$tmp/nur-stacks"; mkdir -p "$d"; echo '{"require":{"laravel/framework":"^13"}}' > "$d/composer.json"; printf 'stack: script\n' > "$d/.coding-standard"
out="$(cd "$d" && env CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$d" bash "$hier/standard-context.sh" --stacks)"
if [ "$out" = "laravel script" ]; then echo "ok    --stacks nennt nur die Stacks"; else echo "FEHLER --stacks nennt nur die Stacks (Ausgabe: $out)"; fehler=$((fehler+1)); fi
d="$tmp/nur-stacks-unerklaert"; mkdir -p "$d"; echo '{"dependencies":{"astro":"^7.0.0"}}' > "$d/package.json"
out="$(cd "$d" && env CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$d" bash "$hier/standard-context.sh" --stacks)"
if [ "$out" = "astro" ]; then echo "ok    --stacks auch ohne Erklärung"; else echo "FEHLER --stacks auch ohne Erklärung (Ausgabe: $out)"; fehler=$((fehler+1)); fi
d="$tmp/nur-stacks-leer"; mkdir -p "$d"
out="$(cd "$d" && env CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$d" bash "$hier/standard-context.sh" --stacks)"
if [ -z "$out" ]; then echo "ok    --stacks ohne Treffer: leer"; else echo "FEHLER --stacks ohne Treffer: leer (Ausgabe: $out)"; fehler=$((fehler+1)); fi

# Größe: Claude Code blendet Hook-Ausgaben über ~2 KB nur als Vorschau ein.
d="$tmp/groesse"; aktiviert "$d"; echo '{"require":{"laravel/framework":"^13"}}' > "$d/composer.json"; printf 'fastapi==0.115.6\n' > "$d/requirements.txt"
bytes=$(lauf "$d" | wc -c)
if [ "$bytes" -lt 1800 ]; then echo "ok    Ausgabe klein genug ($bytes Bytes < 1800)"; else echo "FEHLER Ausgabe zu groß ($bytes Bytes) — wird von Claude Code abgeschnitten"; fehler=$((fehler+1)); fi

echo
if [ "$fehler" -eq 0 ]; then echo "Alle Fälle grün."; else echo "Fehler: $fehler"; exit 1; fi
