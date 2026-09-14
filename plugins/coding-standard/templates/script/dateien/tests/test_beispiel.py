"""Prüfungen für scripts/beispiel.py.

Geprüft wird der Kern, der eine Entscheidung trifft (`zaehle`), und der
Rückgabewert bei fehlender Datei — nicht, dass argparse funktioniert.
"""

from pathlib import Path

from scripts.beispiel import main, zaehle


def test_zaehlt_gleiche_zeilen_zusammen() -> None:
    ergebnis = zaehle(["Apfel", "Birne", "apfel  ", "", "  "])

    assert ergebnis["apfel"] == 2
    assert ergebnis["birne"] == 1
    assert sum(ergebnis.values()) == 3


def test_fehlende_datei_endet_mit_ausgangswert_eins(tmp_path: Path) -> None:
    assert main([str(tmp_path / "gibtesnicht.txt")]) == 1


def test_dry_run_liest_nicht(tmp_path: Path) -> None:
    assert main([str(tmp_path / "gibtesnicht.txt"), "--dry-run"]) == 0


def test_gibt_die_haeufigsten_zeilen_aus(tmp_path: Path) -> None:
    datei = tmp_path / "eingabe.txt"
    datei.write_text("a\nb\na\n", encoding="utf-8")

    assert main([str(datei), "--anzahl", "1"]) == 0
