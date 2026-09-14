---
paths: ['resources/js/**']
---

# Arbeitsoberfläche (Inertia + React)

- **Props typisieren.** Jede Seite deklariert ihre Props als `type`/`interface`; geteilte
  Props gehören in `resources/js/types/global.d.ts`. Kein `any`, kein stillschweigendes
  `unknown` durchreichen — `npm run types:check` ist Teil der Prüfung.
- **Keine Fachlogik im Client.** Rechte, Fristen, Bewertung und Sichtbarkeit entscheidet
  der Server. Die Oberfläche zeigt an, was sie bekommt, und schickt zurück, was eingegeben
  wurde. Eine im Client versteckte Schaltfläche ist keine Berechtigungsprüfung.
- **Inertia-Props sind nicht vertrauenswürdig.** Sie stammen aus derselben Anfrage wie
  alles andere: serverseitig prüfen, was zurückkommt; nie aus einer geteilten Prop auf eine
  Erlaubnis schließen (`auth.isAdmin` steuert nur die Sichtbarkeit im Menü).
- **Zwei Ausnahmelisten pflegen.** `vite.config.ts` trennt `lint.ignorePatterns` und
  `fmt.ignorePatterns`. Erzeugte Dateien (Wayfinder unter `resources/js/actions`, `routes`,
  `wayfinder`; `components/ui`) müssen in **beiden** stehen, sonst schlägt `npm run check`
  an einer Datei fehl, die niemand geschrieben hat. Dieselbe Liste gehört auch in
  `.gitignore`, die Pint- und Larastan-Excludes.

## Weiteres

- Erzeugte Wayfinder-Dateien nie von Hand ändern — sie entstehen beim Bau neu.
- Routen über die Wayfinder-Helfer ansprechen, keine handgeschriebenen Pfade.
- Alle sichtbaren Texte Deutsch mit echten Umlauten; Bezeichner bleiben ASCII.
- Formatierung und Lint laufen über `npm run check` (Korrektur `npm run check:fix`), nicht
  über ein eigenes Prettier oder ESLint.
