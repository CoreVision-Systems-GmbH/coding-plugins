---
paths: ['tests/**']
---

# Prüfungen

- **Ohne Datenbank.** `composer check` = Coding-Standards (PHPCS), statische Analyse
  (PHPStan) und die Strukturprüfung. Was eine laufende Site braucht — Anmeldung, Editor,
  Uploads, ein Plugin —, wird im lokalen Verbund geprüft (`compose.dev.yaml`) und im PR als
  Klickweg festgehalten: „geprüft: …“.
- **Jeder Fix bringt eine Prüfung mit,** die ohne die Korrektur rot wäre: eine Regel in
  `phpcs.xml`, eine Zusicherung in `tests/pruefe-struktur.php` oder ein PHPStan-Befund.
- `tests/pruefe-struktur.php` ist ein Skript ohne Framework: Zusicherungen als Zeilen,
  deutsche Meldungen, Ausgangswert ≠ 0 bei Befund. Es prüft, was WordPress selbst erst zur
  Laufzeit merken würde: Theme vollständig, `theme.json` gültig, ENV-Schema deckt die
  Konfiguration, WordPress auf eine Nebenfassung gepinnt.
