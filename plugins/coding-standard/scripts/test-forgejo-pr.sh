#!/usr/bin/env bash
# Prüft forgejo-pr.sh gegen eine curl-Attrappe: Remote-Formen, view (Treffer, kein PR, Störung),
# create (Draft-Präfix, Umlaute über eine Datei), checks und die Bindung von $FORGEJO_TOKEN an den
# eigenen Host. Kein Netz, nichts außerhalb von $TMPDIR.
#
#     bash plugins/coding-standard/scripts/test-forgejo-pr.sh

set -u

hier="$(cd "$(dirname "$0")" && pwd)"
skript="$hier/forgejo-pr.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fehler=0
ok()      { echo "ok     $1"; }
nichtok() { echo "FEHLER $1"; fehler=$((fehler + 1)); }

# Die Attrappe antwortet je Pfad, protokolliert URL, Körper und ob das Token mitkam. STOERUNG=ja
# lässt jede Anfrage wie curl -f bei HTTP 500 scheitern (Exit 22).
protokoll="$tmp/curl.log"
attrappe="$tmp/attrappe"; mkdir -p "$attrappe"
cat > "$attrappe/curl" <<EOF
#!$BASH
konfig="\$(cat)"; url=""; koerper=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        --data-binary) koerper="\$(cat "\${2#@}")"; shift 2 ;;
        -X|-H|-K) shift 2 ;;
        -*) shift ;;
        *) url="\$1"; shift ;;
    esac
done
printf '%s|%s|%s\n' "\$url" "\$(grep -c 'token geheim' <<<"\$konfig")" "\$koerper" >> "$protokoll"
[ "\${STOERUNG:-}" = ja ] && { echo "curl: (22) 500" >&2; exit 22; }
case "\$url" in
    */pulls\?state=open*) echo '[{"number":7,"html_url":"https://forge.test/CVS/werkzeug/pulls/7","title":"WIP: feat: probe","head":{"ref":"feat/probe"}}]' ;;
    */pulls) echo '{"html_url":"https://forge.test/CVS/werkzeug/pulls/8"}' ;;
    */commits/*/status) echo '{"state":"success","statuses":[{"context":"tests / ci (pull_request)","status":"success","target_url":"/x"}]}' ;;
    *) echo "curl-Attrappe: unerwartet \$url" >&2; exit 7 ;;
esac
EOF
chmod +x "$attrappe/curl"

repo="$tmp/werkzeug"
git init -q -b main "$repo"
git -C "$repo" -c user.name=Probe -c user.email=probe@example.invalid commit -q --allow-empty -m start
git -C "$repo" switch -q -c feat/probe

# Ohne Credential-Helper: keine globale oder System-Konfiguration, kein Askpass.
lauf() { # <remote> <argumente…> — Ausgabe in AUSGABE, Status in STATUS
    local remote="$1"; shift
    git -C "$repo" remote remove origin 2>/dev/null
    git -C "$repo" remote add origin "$remote"
    AUSGABE="$(cd "$repo" && PATH="$attrappe:$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        GIT_ASKPASS='' bash "$skript" "$@" 2>&1)"
    STATUS=$?
}

export FORGEJO_URL=https://forge.test FORGEJO_TOKEN=geheim

echo "== view"
: > "$protokoll"
lauf https://forge.test/CVS/werkzeug.git view
[ "$STATUS" -eq 0 ] && [ "$AUSGABE" = "7 https://forge.test/CVS/werkzeug/pulls/7 draft" ] \
    && ok "view findet den PR des Zweigs und erkennt den Draft" || nichtok "view findet den PR des Zweigs ($STATUS: $AUSGABE)"
grep -q '^https://forge.test/api/v1/repos/CVS/werkzeug/pulls?state=open&limit=50|1|' "$protokoll" \
    && ok "API-Adresse aus HTTPS-Remote, Token mitgesendet" || nichtok "API-Adresse aus HTTPS-Remote, Token mitgesendet"

: > "$protokoll"
lauf ssh://git@forge.test:2222/CVS/werkzeug.git view
grep -q '^https://forge.test/api/v1/repos/CVS/werkzeug/' "$protokoll" \
    && ok "API-Adresse aus ssh://-Remote mit Port" || nichtok "API-Adresse aus ssh://-Remote mit Port"

git -C "$repo" switch -q -c feat/anderer
lauf https://forge.test/CVS/werkzeug.git view
[ "$STATUS" -eq 3 ] && ok "view ohne PR endet mit 3" || nichtok "view ohne PR endet mit 3 (war $STATUS)"
STOERUNG=ja lauf https://forge.test/CVS/werkzeug.git view
[ "$STATUS" -ne 0 ] && [ "$STATUS" -ne 3 ] \
    && ok "view bei Störung endet nicht mit 3 ($STATUS)" || nichtok "view bei Störung endet nicht mit 3 (war $STATUS)"
git -C "$repo" switch -q feat/probe

echo "== create"
printf '## Was\nPrüfweg mit Umlauten: äöü ß.\n' > "$tmp/body.md"
: > "$protokoll"
lauf https://forge.test/CVS/werkzeug.git create --draft --title "feat: Größe prüfen" --body-file "$tmp/body.md"
[ "$AUSGABE" = "https://forge.test/CVS/werkzeug/pulls/8" ] && ok "create nennt die URL" || nichtok "create nennt die URL ($AUSGABE)"
grep -q '"title": "WIP: feat: Größe prüfen"' "$protokoll" && ok "Draft als Titelpräfix WIP:, Umlaute erhalten" \
    || nichtok "Draft als Titelpräfix WIP:, Umlaute erhalten"
grep -q '"head": "feat/probe", "base": "main"' "$protokoll" && ok "Zweig und Basis im Körper" || nichtok "Zweig und Basis im Körper"
grep -q 'äöü ß' "$protokoll" && ok "Body mit Umlauten unverändert" || nichtok "Body mit Umlauten unverändert"
lauf https://forge.test/CVS/werkzeug.git create --title "x"
[ "$STATUS" -ne 0 ] && ok "create ohne --body-file wird abgewiesen" || nichtok "create ohne --body-file wird abgewiesen"

echo "== checks"
lauf https://forge.test/CVS/werkzeug.git checks
grep -q '^gesamt: success' <<<"$AUSGABE" && grep -q 'tests / ci (pull_request): success' <<<"$AUSGABE" \
    && ok "checks nennt Gesamtstand und Einzelprüfung" || nichtok "checks nennt Gesamtstand und Einzelprüfung ($AUSGABE)"

echo "== Token und Hosts"
lauf https://github.com/CVS/werkzeug.git view
[ "$STATUS" -ne 0 ] && grep -q 'gh pr' <<<"$AUSGABE" && ok "GitHub-Remote verweist auf gh pr" || nichtok "GitHub-Remote verweist auf gh pr"
: > "$protokoll"
lauf https://fremd.example/CVS/werkzeug.git view
[ "$STATUS" -ne 0 ] && grep -q 'Kein Token für fremd.example' <<<"$AUSGABE" && [ ! -s "$protokoll" ] \
    && ok "FORGEJO_TOKEN geht nicht an einen fremden Host" || nichtok "FORGEJO_TOKEN geht nicht an einen fremden Host ($AUSGABE)"

echo
if [ "$fehler" -eq 0 ]; then
    echo "Alle Fälle grün."
else
    echo "Fehler: $fehler"
    exit 1
fi
