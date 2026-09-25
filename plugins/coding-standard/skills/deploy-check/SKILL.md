---
name: deploy-check
description: Prüfliste vor dem Update einer Kundeninstanz — Ziel-Tag, Migrationen, ENV-Schlüssel, Drift, Sicherung und Gesundheit. Liest nur, führt kein Update aus. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: <kunde>/<produkt> <tag>
---

# Deploy-Check

Instanz und Ziel-Tag aus dem Aufruf: `$ARGUMENTS`
(Erwartet: `<kunde>/<produkt> <tag>`, z. B. `musterkunde/produkt v1.4.0`)

Dieser Skill **führt kein Update aus**. Er prüft, ob eines gefahren werden darf, und
liefert ein Go/No-Go je Punkt.

Fehlt eines der beiden Argumente: fragen, nicht raten.

## Regeln

- Auf dem Server ausschließlich **lesende** Befehle: `cat`, `ls`, `stat`, `df`, `cut`,
  `docker ps`, `docker inspect`, `curl`. Kein `docker compose up`, kein `pull`, kein
  Schreiben, kein Neustart.
- Werte aus `.env` werden **nie** gelesen, ausgegeben oder in den Bericht übernommen —
  nur Schlüsselnamen (`cut -d= -f1`).
- Bei einem No-Go **keine** Deploy-Befehle vorschlagen. Erst den Punkt klären.
- Was nicht geprüft werden konnte, wird als „ungeprüft" berichtet, nicht als „grün".

## Grundlage lesen

Im `deployments`-Repo den Instanzordner `customers/<kunde>/<produkt>/` lesen:

- `INSTANZ.md` — Host, SSH-Alias, Verzeichnis auf dem Server, laufende Version, Besonderheiten
- `env.keys` — die Schlüssel, die diese Instanz haben muss
- `compose.override.yaml` — instanzspezifische Abweichungen

Aus `INSTANZ.md` ergeben sich Host und Instanzverzeichnis für alle weiteren Prüfungen.
Fehlt der Ordner oder eine der Dateien: abbrechen und sagen, was fehlt.

Auf Prod-Servern nach dem Server-Baustein (`setup-server.sh --rolle prod`) liegt die Instanz
unter `/opt/apps/<app>/`; `ssh <host> sudo rollout <app> status` zeigt laufende Fassung,
Container, geplante Termine und die letzten Läufe — lesend, als Ausgangspunkt für (a) und (f).

## (a) Ziel-Tag

- Existiert `<tag>` als GitHub-Release im Produkt-Repo?
  `gh release view <tag> --repo <owner>/<produkt>`
- Enthalten die Release-Notizen einen Image-Digest (`sha256:…`)?

Ohne Digest ist unklar, was ausgerollt würde → No-Go.

## (b) Migrationen

- Laufende Version aus `INSTANZ.md` als `v<alt>`, Ziel als `v<neu>`.
- `git diff --name-only v<alt>..v<neu> -- database/migrations`
- Jede geänderte Migration ansehen und einordnen: **rein additiv** oder nicht.
  Nicht additiv ist alles mit `dropColumn`, `dropTable`, `change()` oder `renameColumn`.

Rein additiv → Go. Sonst → No-Go mit Hinweis, dass ein Wartungsfenster, eine Sicherung
und ein Rückweg geplant werden müssen (erst erweitern, später entfernen).

## (c) ENV-Schlüssel

- Auf dem Server: `cut -d= -f1 <instanzverzeichnis>/.env | sort` — **nur Schlüssel**.
- Gegen `env.keys` aus dem Repo vergleichen.
- Gegen `.env.example` des Ziel-Tags vergleichen
  (`git show v<neu>:.env.example | grep -oE '^[A-Z_]+' | sort`).

Fehlende Schlüssel → No-Go (die Anwendung startet oder arbeitet sonst falsch).
Überzählige Schlüssel → Hinweis, kein No-Go.

## (d) Drift

- Dateien im Instanzverzeichnis auf dem Server gegen den Instanzordner im Repo diffen
  (`compose.yaml`, `compose.override.yaml`, Caddy-Snippets, Entrypoint-Skripte).
- Änderungsdatum der Serverdateien (`stat -c '%y %n'`) gegen das Datum des letzten Commits
  im Instanzordner halten.

Ist eine Serverdatei neuer als der letzte Commit oder weicht ihr Inhalt ab, wurde am
lebenden System editiert → No-Go, bis die Änderung ins Repo zurückgeholt oder verworfen ist.

## (e) Sicherung und Platz

- Jüngste Sicherung vorhanden und **jünger als 24 Stunden**?
- Freier Plattenplatz **über 20 %** (`df -h <instanzverzeichnis>`)?

Beides sind harte No-Gos: ohne frische Sicherung gibt es keinen Rückweg, ohne Platz
scheitert das Ziehen des Images oder ein Dump.

## (f) Gesundheit und laufende Version

- `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/up` im App-Container
  bzw. über den Edge-Proxy.
- Laufende Version: `docker inspect` auf das Image-Tag bzw. den Footer der Anwendung.

Läuft die Instanz jetzt schon nicht sauber, wird das Update nichts heilen → No-Go, erst
den laufenden Fehler klären.

## (g) Härtung der laufenden Container

- Im Instanzverzeichnis, nur lesend:
  `docker inspect --format '{{.Name}} ro={{.HostConfig.ReadonlyRootfs}} caps={{.HostConfig.CapDrop}} sec={{.HostConfig.SecurityOpt}} log={{.HostConfig.LogConfig.Config}}' $(docker compose ps -q)`
- Soll je Container: `ro=true`, `caps=[ALL]`, `sec=[no-new-privileges:true]`, Log-Rotation
  (`max-size`, `max-file`) — so, wie es die `compose.yaml` des Ziel-Tags vorgibt.
- Eine Abweichung ist kein No-Go, aber ein Befund: Die Härtung kommt mit dem nächsten
  `docker compose up -d` aus dem Repo. Steht sie dort nicht (älteres Projekt), fehlt sie auch
  nach dem Update — dann `compose.yaml` aus `templates/<stack>/dateien` nachziehen.

## Ausgabe

```text
Instanz:  <kunde>/<produkt>   Host: <host>   Laufend: v<alt>   Ziel: v<neu>

| # | Prüfpunkt                          | Ergebnis | Befund |
|---|------------------------------------|----------|--------|
| a | Ziel-Tag und Digest                | Go/No-Go | …      |
| b | Migrationen additiv                | Go/No-Go | …      |
| c | ENV-Schlüssel vollständig          | Go/No-Go | …      |
| d | Kein Drift auf dem Server          | Go/No-Go | …      |
| e | Sicherung < 24 h, Platz > 20 %     | Go/No-Go | …      |
| f | Gesundheit und laufende Version    | Go/No-Go | …      |
| g | Härtung der Container              | Go/Befund | …     |

Empfehlung: <Update freigegeben | Update NICHT fahren, weil …>
Ungeprüft:  <was nicht festgestellt werden konnte>
```

Bei durchgehendem Go: die Empfehlung aussprechen und darauf hinweisen, dass das Update
selbst ein eigener, bestätigter Schritt ist — dieser Skill fährt es nicht. Auf Prod-Servern mit
Server-Baustein ist das `/rollout <app> jetzt|"<termin>" <tag>`.
