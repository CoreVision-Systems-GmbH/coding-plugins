"""Konfiguration der Datenbank.

Ein fehlendes oder leeres Passwort soll den Start verhindern, nicht erst die
erste Abfrage; die Fehlermeldung darf das Passwort nicht zeigen; und
Sonderzeichen aus dem Tresor dürfen die Verbindungsadresse nicht zerlegen.
Die Testwerte kommen aus tests/conftest.py; ``_env_file=None`` hält eine
lokale .env heraus.
"""

import pytest
from pydantic import ValidationError

from app.settings import Settings


def test_fehlendes_passwort_verhindert_den_start(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("DB_PASSWORD")

    with pytest.raises(ValidationError, match="DB_PASSWORD"):
        Settings(_env_file=None)


def test_leeres_passwort_verhindert_den_start(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DB_PASSWORD", "")

    with pytest.raises(ValidationError, match="DB_PASSWORD"):
        Settings(_env_file=None)


def test_fehlermeldung_verraet_das_passwort_nicht(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DB_PASSWORD", "Kx9-geheim-zz")
    monkeypatch.delenv("DB_DATABASE")

    with pytest.raises(ValidationError) as fehler:
        Settings(_env_file=None)

    assert "Kx9-geheim-zz" not in str(fehler.value)


def test_sonderzeichen_bleiben_in_der_adresse_maskiert(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DB_PASSWORD", "p@ss:w/rt%")

    adresse = Settings(_env_file=None).database_url

    assert adresse == "postgresql+psycopg://test:p%40ss%3Aw%2Frt%25@test.invalid:5432/test"
