---
name: rollout
description: Spielt ein GitHub-Release einer Anwendung auf dem Prod-Server ein — sofort oder zu einem geplanten Termin — oder zeigt und sagt Termine ab. Führt `rollout` auf dem Server per SSH aus, erst nach ausdrücklicher Freigabe. Nur vom Nutzer aufrufen.
disable-model-invocation: true
argument-hint: <app> [jetzt|"JJJJ-MM-TT HH:MM"|liste|absagen <id>|status] [tag]
---

# Rollout

Auftrag: `$ARGUMENTS`

Der Prod-Server holt eine Fassung **nur auf Auftrag**: sofort oder zu einem einmaligen Termin.
Dieser Skill bereitet den Auftrag vor, holt die Freigabe und führt ihn per SSH aus. Er ändert
nichts im Repository.

## Regeln

- **Ohne ausdrückliches Ja des Nutzers kein `jetzt` und kein `planen`.** Lesen (`liste`,
  `status`) darf ohne Rückfrage laufen.
- Nur Releases (Tags `vX.Y.Z`), nie ein Branch oder ein loser Stand.
- Werte aus `.env` werden nie gelesen oder ausgegeben.
- Scheitert der Rollout, die Ausgabe wörtlich zitieren und den Rückweg nennen
  (`rollout <app> jetzt <vorheriger-tag>`) — **nicht** selbst ausführen.

## 1. Ziel klären

- Anwendung aus dem Aufruf; fehlt sie: fragen.
- Prod-Server: aus `docs/status.md` oder `CLAUDE.md` des Projekts (SSH-Alias im Tailnet). Steht
  er nirgends: fragen und vorschlagen, ihn in die `CLAUDE.md` unter „Betrieb“ einzutragen.
- Zeitpunkt: `jetzt`, ein Termin `"JJJJ-MM-TT HH:MM"` (Europe/Vienna), `liste`, `absagen <id>`
  oder `status`. Ein Termin in natürlicher Sprache („Freitag 2 Uhr“) wird in dieses Format
  übersetzt und im Freigabetext ausgeschrieben.

## 2. Lage zeigen (lesend)

```bash
ssh <prod> sudo rollout <app> status
gh release list --repo <eigentümer>/<repo> --limit 5
```

Ziel-Tag: der angegebene, sonst das neueste Release. Aus `CHANGES.md` des Projekts die
Abschnitte zwischen laufender Fassung und Ziel-Tag zusammenfassen — besonders Migrationen und
neue ENV-Schlüssel (dann vorher `/deploy-check` empfehlen).

## 3. Freigabe

Kurz vorlegen und auf ein ausdrückliches Ja warten:

> Rollout **<app>** auf **<prod>**: <laufend> → **<ziel-tag>**, **jetzt** bzw. am **<termin> (Europe/Vienna)**.
> Änderungen: … · Migration: ja/nein · neue ENV-Schlüssel: … · Rückweg: `rollout <app> jetzt <laufend>`

## 4. Ausführen

```bash
ssh <prod> sudo rollout <app> jetzt <ziel-tag>
ssh <prod> sudo rollout <app> planen "<JJJJ-MM-TT HH:MM>" <ziel-tag>
ssh <prod> sudo rollout liste
ssh <prod> sudo rollout absagen <id>
```

Den Tag immer ausdrücklich mitgeben — so kommt genau die freigegebene Fassung, auch wenn bis
zum Termin ein neueres Release erscheint.

## 5. Bericht

Vier Zeilen: Ziel und Fassung · Ergebnis (Ausgabe von `rollout`, bei Termin die Id) · Rückweg ·
Offen. Bei einem Termin: wie man ihn absagt (`/rollout <app> absagen <id>`).
