---
paths: ['tests/**']
---

# Tests

- **Getestet wird, was entscheidet.** Auswahl, Umrechnung, Parsen, Idempotenz. Ein Aufruf,
  der nur fremde Befehle hintereinanderschaltet, belegt sich mit `--dry-run` statt mit
  einem Test, der nur Mocks prüft.
- **Jedes Werkzeug hat mindestens einen Fall für den Fehlerausgang.** Ein Skript, das bei
  falscher Eingabe mit 0 endet, ist gefährlicher als eines, das gar nicht läuft.
- **Idempotenz ist ein Testfall**, kein Vorsatz: zweimal aufrufen, Ergebnis vergleichen.

## Konventionen dieses Repos

- Python: `pytest`, Testnamen auf Deutsch und in ganzen Aussagen, jede Testfunktion mit
  `-> None`. Dateien in `tests/`, benannt nach dem geprüften Werkzeug.
- Shell: eigene Prüfdatei `tests/test_<werkzeug>_sh.sh` ohne fremdes Rahmenwerk — sie zählt
  Fehler und endet mit einem Ausgangswert ungleich 0. Bats lohnt erst, wenn die Suite wächst.
- Nichts außerhalb von `$TMPDIR` anlegen; jeder Test räumt hinter sich auf (`trap ... EXIT`).
- Keine echten Zugangsdaten, keine Netzaufrufe, keine Abhängigkeit vom Zustand des Rechners.
