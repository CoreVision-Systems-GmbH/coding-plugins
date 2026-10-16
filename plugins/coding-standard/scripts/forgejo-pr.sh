#!/usr/bin/env bash
# forgejo-pr.sh — Pull Requests auf Forgejo für /pr, so wie dort `gh pr` auf GitHub.
#
#     forgejo-pr.sh view                                   PR des aktuellen Zweigs: Nummer, URL, Draft
#                                                          (Exit 3: kein offener PR)
#     forgejo-pr.sh create --title "<t>" --body-file <f> [--draft] [--base main]
#     forgejo-pr.sh checks                                 Statusprüfungen des aktuellen Stands
#
# Server, Eigentümer und Repo kommen aus `origin`. Token aus $FORGEJO_TOKEN (nur für den Host von
# $FORGEJO_URL, Vorgabe gitts), sonst aus dem Git-Credential-Helper. Einen Draft kennt Forgejo als Titel mit Präfix „WIP: “.

set -euo pipefail

abbruch() { printf 'FEHLER: %s\n' "$1" >&2; exit 1; }

py() { # JSON auswerten — python3 kann unter Windows ein Store-Platzhalter sein, deshalb erst probieren
    local p
    for p in python3 python; do
        if "$p" -c 'import json' >/dev/null 2>&1; then "$p" -X utf8 -I "$@"; return; fi
    done
    abbruch "python fehlt — für die Auswertung der Forgejo-API nötig."
}

remote="$(git remote get-url origin 2>/dev/null)" || abbruch "Kein Remote 'origin'."
r="${remote%.git}"; r="${r%/}"
REPO="${r##*/}"; r="${r%/*}"; OWNER="${r##*[/:]}"
HOST="${remote#*://}"; HOST="${HOST#*@}"; HOST="${HOST%%[:/]*}"
[ "$HOST" != github.com ] || abbruch "origin liegt auf GitHub — dort gh pr nehmen."
API="https://$HOST/api/v1/repos/$OWNER/$REPO"

# $FORGEJO_TOKEN gilt nur für den eigenen Forgejo — sonst ginge es an jeden Host, auf den
# origin zeigt. Für alle anderen Hosts fragt der Credential-Helper je Host.
eigener_host="${FORGEJO_URL:-https://gitts.cvsystems.net}"; eigener_host="${eigener_host#*://}"; eigener_host="${eigener_host%%/*}"
TOKEN=""
[ "$HOST" != "$eigener_host" ] || TOKEN="${FORGEJO_TOKEN:-}"
if [ -z "$TOKEN" ]; then
    TOKEN="$(printf 'protocol=https\nhost=%s\n\n' "$HOST" \
        | GIT_ASKPASS='' GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never git credential fill 2>/dev/null \
        | sed -n 's/^password=//p' | tr -d '\r' || true)"
fi
[ -n "$TOKEN" ] || abbruch "Kein Token für $HOST: \$FORGEJO_TOKEN setzen oder im Credential-Helper hinterlegen."

api() { # <methode> <pfad> [datei mit json-körper] — Körper auf stdout, Fehler ab HTTP 400
    printf 'header = "Authorization: token %s"\n' "$TOKEN" \
        | curl -fsS -K - -X "$1" -H 'Content-Type: application/json' ${3:+--data-binary "@$3"} "$API$2"
}

zweig="$(git rev-parse --abbrev-ref HEAD)"

case "${1:-}" in
    view)
        # Exit 3 heißt „kein PR für diesen Zweig“ — ein API-Fehler endet anders (curl, Exit 22),
        # damit /pr bei einer Störung nicht doppelt anlegt.
        offen="$(api GET "/pulls?state=open&limit=50")"
        py -c '
import json, sys
for p in json.loads(sys.argv[2]):
    if p["head"]["ref"] == sys.argv[1]:
        print(p["number"], p["html_url"], "draft" if p["title"].startswith("WIP:") else "ready")
        sys.exit(0)
sys.exit(3)' "$zweig" "$offen"
        ;;
    create)
        shift
        titel=""; body=""; draft=0; basis=main
        while [ $# -gt 0 ]; do
            case "$1" in
                --title)     titel="${2:?}"; shift 2 ;;
                --body-file) body="${2:?}"; shift 2 ;;
                --draft)     draft=1; shift ;;
                --base)      basis="${2:?}"; shift 2 ;;
                *)           abbruch "Unbekannte Option: $1" ;;
            esac
        done
        [ -n "$titel" ] && [ -f "$body" ] || abbruch "create braucht --title und eine lesbare --body-file."
        [ "$draft" -eq 0 ] || titel="WIP: $titel"
        anfrage="$(mktemp)"; trap 'rm -f "$anfrage"' EXIT
        # Über eine Datei und UTF-8, nicht inline — sonst gehen Umlaute unter Windows verloren.
        py -c '
import json, sys
body = open(sys.argv[4], encoding="utf-8").read()
json.dump({"title": sys.argv[1], "head": sys.argv[2], "base": sys.argv[3], "body": body},
          open(sys.argv[5], "w", encoding="utf-8"), ensure_ascii=False)' \
            "$titel" "$zweig" "$basis" "$body" "$anfrage"
        api POST "/pulls" "$anfrage" | py -c 'import json,sys; print(json.load(sys.stdin)["html_url"])'
        ;;
    checks)
        sha="$(git rev-parse HEAD)"
        api GET "/commits/$sha/status" | py -c '
import json, sys
d = json.load(sys.stdin)
print("gesamt:", d.get("state") or "keine Prüfungen")
for s in d.get("statuses") or []:
    print(" ", s["context"] + ":", s["status"], s.get("target_url") or "")'
        ;;
    *)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
