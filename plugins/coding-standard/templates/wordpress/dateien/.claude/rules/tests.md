---
paths: ['tests/**']
---

# Prüfungen

- **Ohne Datenbank.** `composer check` = Coding-Standards (PHPCS), statische Analyse
  (PHPStan) und die Strukturprüfung. Was eine laufende Site braucht — Anmeldung, Editor,
  Uploads, ein Plugin —, wird auf der Dev-Instanz geprüft (`deploy/dev.sh up`) und im PR als
  Klickweg festgehalten: „geprüft: …“.
- **Jeder Fix bringt eine Prüfung mit,** die ohne die Korrektur rot wäre: eine Regel in
  `phpcs.xml`, eine Zusicherung in `tests/pruefe-struktur.php` oder ein PHPStan-Befund.
- `tests/pruefe-struktur.php` ist ein Skript ohne Framework: Zusicherungen als Zeilen,
  deutsche Meldungen, Ausgangswert ≠ 0 bei Befund. Es prüft, was WordPress selbst erst zur
  Laufzeit merken würde: Theme vollständig, `theme.json` gültig, ENV-Schema deckt die
  Konfiguration, WordPress auf eine Nebenfassung gepinnt.
- **Regressionsliste:** Jeder behobene Fehler wird eine benannte Zusicherung in
  `tests/pruefe-struktur.php` oder eine Zeile in `deploy/smoke.txt` — mit Vorfall und Fassung
  im Meldetext (`Vorfall 2026-09-25, v1.4.2`).
- **Synthetische Inhalte auf der Dev-Instanz:** keine echten Personen, Adressen nur
  `example.org` & Co.; ein Auszug aus der Produktions-Datenbank gehört nicht auf Dev.
