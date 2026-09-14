---
paths: ['app/Filament/**', 'app/Providers/Filament/**']
---

# Verwaltungsoberfläche (Filament)

- **Eigener Middleware-Stapel.** Das Panel benutzt **nicht** die `web`-Gruppe, sondern die
  Liste in `AdminPanelProvider::panel()`. App-weite Sicherheits-Middleware wirkt unter
  `/admin` nur, wenn sie dort noch einmal steht. Für Livewire-Anfragen zusätzlich
  `isPersistent: true` setzen — sonst führt Filament sie ausschließlich beim ersten
  Seitenaufruf aus. Dass Aktionen trotzdem geprüft würden, hinge dann allein daran, dass
  Livewire seinen gemeinsamen Update-Endpunkt in die `web`-Gruppe zwingt — eine Klammer
  außerhalb des Panels, die mit jedem Fassungssprung fallen kann.
- **Policies je Resource.** Jede Resource braucht eine Policy und Tests dazu, paarweise
  (erlaubt und verweigert). `canAccessPanel()` ist die Tür zum Panel, nicht der Schutz der
  einzelnen Datensätze.
- **Keine Fachlogik in Resources.** Resource, Page und Widget beschreiben nur die
  Oberfläche. Was entschieden oder gerechnet wird, gehört nach `app/Actions/` — dieselbe
  Regel muss auch die Inertia-Oberfläche aufrufen können.

## Weiteres

- Ein Anmeldeweg für die ganze Anwendung: kein `->login()`, kein eigener zweiter Faktor im
  Panel. Wer nicht angemeldet ist, geht über `/login` und kommt zurück.
- Der Panel-Aufbau muss auch ohne Datenbank durchlaufen (Marke, Farben, Schrift aus
  Einstellungen defensiv lesen), sonst bricht `migrate` und der Abbild-Bau.
- Abfragen in Tabellen und Widgets über die vorhandenen Scopes führen — keine ungefilterten
  Gesamtabfragen, keine N+1-Ketten in Spalten.
- Beschriftungen und Meldungen auf Deutsch mit echten Umlauten.
