# 0001 — Projektstart: {{NAME}} auf {{STACK_LABEL}}

> Datum: {{DATE}}
> Status: Angenommen

## Kontext

{{PURPOSE}}

Auftraggeber/Instanz: {{CUSTOMER}}. Das Projekt startet auf der grünen Wiese; es gibt weder
Bestandscode noch eine Datenmigration. Entschieden werden muss, auf welchem Stack gebaut
wird und wie geliefert wird — beides ist später teuer zu ändern.

<!-- Ergänzen: Mengengerüst (Nutzer, Datenmenge), Fristen, Budget, vorhandene Systeme,
     mit denen es sich vertragen muss. -->

## Entscheidung

**Entschieden:** {{NAME}} wird auf {{STACK_LABEL}} gebaut und nach Firmenstandard
(`coding-standard@corevision`) geführt: Kern und Stack-Overlay gelten ab dem ersten Commit,
das Repository liegt privat unter `{{OWNER}}/{{NAME}}`, geliefert wird über Tags `vX.Y.Z`.

**Verworfen:**

| Alternative | Warum nicht |
| ----------- | ----------- |
|             |             |

<!-- Die verworfenen Wege sind der eigentliche Wert einer ADR. Mindestens den nächstliegenden
     anderen Stack eintragen und den Grund, der gegen ihn sprach. -->

## Folgen

**Positiv:**

- Ein bekannter Stack: Werkzeugkette, CI, Lieferweg und Reviewer-Agents sind vorhanden.
- Der Standard wird in jeder Session automatisch geladen; niemand muss ihn aufrufen.

**Negativ:**

- Der Stack bringt seine eigenen Zwänge mit (siehe Overlay, Abschnitt „Fallen").

**Zu tun:**

- `docs/status.md` mit dem ersten echten Arbeitsstand füllen.
- Beim ersten Feature die Karte in `CLAUDE.md` ausfüllen.
