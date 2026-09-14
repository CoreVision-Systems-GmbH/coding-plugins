#!/usr/bin/env python3
"""Beispielwerkzeug in Python — Vorlage für ein echtes Skript.

Es fasst Zeilen einer Textdatei zu einer Auszählung zusammen. Der Zweck ist
nicht die Aufgabe, sondern die Form: ``--help``, ``--dry-run``, ein Kern, der
ohne Ein- und Ausgabe prüfbar ist, Meldungen nach stderr, Ergebnis nach stdout,
Ausgangswert ungleich 0 bei Fehlern.

Aufruf:      python scripts/beispiel.py <datei> [--dry-run]
Ändert:      nichts — liest nur
Rückweg:     entfällt
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path


def zaehle(zeilen: list[str]) -> Counter[str]:
    """Zählt die nicht leeren Zeilen, normalisiert auf Kleinschreibung.

    Der Kern des Werkzeugs steht bewusst hier: eine Funktion ohne Datei, ohne
    Argumente, ohne Ausgabe — genau das, was sich prüfen lässt.
    """
    return Counter(z.strip().lower() for z in zeilen if z.strip())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="beispiel.py",
        description="Zählt die Zeilen einer Textdatei und gibt die häufigsten aus.",
        epilog="Ändert nichts. Ein Rückweg ist deshalb nicht nötig.",
    )
    parser.add_argument("datei", type=Path, help="Zu lesende Textdatei.")
    parser.add_argument(
        "--anzahl", type=int, default=5, help="Wie viele Zeilen ausgegeben werden (Vorgabe: 5)."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Nur zeigen, was gelesen würde. Liest die Datei nicht.",
    )
    args = parser.parse_args(argv)

    if args.dry_run:
        print(f"Würde lesen: {args.datei}", file=sys.stderr)
        return 0

    if not args.datei.is_file():
        print(f"FEHLER: Datei nicht gefunden: {args.datei}", file=sys.stderr)
        return 1

    zeilen = args.datei.read_text(encoding="utf-8").splitlines()
    for zeile, anzahl in zaehle(zeilen).most_common(args.anzahl):
        print(f"{anzahl}\t{zeile}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
