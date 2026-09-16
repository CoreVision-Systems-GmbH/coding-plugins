# {{ADR_NR}} — Aufnahme in den Firmenstandard: {{NAME}} ({{STACK_LABEL}})

> Datum: {{DATE}}
> Status: Angenommen

## Kontext

{{PURPOSE}}

Auftraggeber/Instanz: {{CUSTOMER}}. Das Projekt ist nicht mit `/projekt-neu` entstanden; es hat
eine eigene Geschichte, Ablage und Werkzeugkette. Es soll unter den Firmenstandard
(`coding-standard@corevision`), ohne umgebaut zu werden: Der Kern gilt sofort, das Overlay
sinngemäß, und was abweicht, steht hier — bewusst und mit Grund. Eine undokumentierte
Abweichung ist eine Insel; eine dokumentierte ist eine Entscheidung.

## Entscheidung

**Entschieden:** {{NAME}} wird ab {{DATE}} nach Firmenstandard geführt. Stufe 0 (Erklärung)
und Stufe 1 (Kontext-Dateien) sind mit dieser ADR angelegt. Ablage, Fassungen und
Werkzeugnamen des Repos bleiben, wie sie sind; die `CLAUDE.md` nennt die echten Befehle.

**Verworfen:**

| Alternative | Warum nicht |
| ----------- | ----------- |
| Neu anlegen mit `/projekt-neu` und den Code umziehen | Kostet Tage, bringt keinen Nutzer-Wert, und der Standard verlangt es nicht — er verlangt die Kern-Regeln, keine Ordnerstruktur. |
| Ohne Erklärung weiterarbeiten | Dann gelten Kern, Git-Guard und Reviewer nicht; jede Session fängt bei null an. |

## Folgen

**Positiv:**

- Kern und Overlay werden in jeder Session automatisch geladen; PR-Fluss, Changelog und
  Beweis statt Behauptung gelten ab jetzt.
- Lücken gegenüber dem Betriebsvertrag sind benannt statt vergessen.

**Negativ:**

- Das Overlay beschreibt den Zielzustand, nicht den Ist-Zustand — bis die Lücken geschlossen
  sind, muss jede Session die Abweichungen kennen (`CLAUDE.md`, Abschnitt „Fallen“).

**Bewusst so belassen** (jeweils mit Grund — sonst ist es keine Entscheidung, sondern eine Lücke):

-

**Zu tun** (je Punkt ein eigener PR; Stand und Reihenfolge in `docs/status.md`):
{{LUECKEN}}
