"""Die eine Stelle, an der Konfiguration gelesen wird.

Jeder Wert kommt aus der Umgebung, nirgendwo sonst. Verstreute
``os.environ.get``-Aufrufe machen Konfiguration unauffindbar; deshalb steht hier
alles beisammen und der Rest der Anwendung fragt ``get_settings()``.
"""

from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Konfiguration des Dienstes.

    Alle Schlüssel tragen den Präfix ``{{ENV_PREFIX}}`` — Ausnahme ist die
    ausgelieferte Fassung, die aus dem Abbild kommt und dort ``APP_IMAGE_VERSION``
    heißt.
    """

    model_config = SettingsConfigDict(
        env_prefix="{{ENV_PREFIX}}",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Die ausgelieferte Fassung. Das Abbild setzt sie beim Bau; außerhalb eines
    # Containers steht hier "dev". Sichtbar in /healthz — bei einer Rückfrage
    # steht damit ohne Serverzugang fest, welcher Stand läuft.
    version: str = Field(default="dev", validation_alias="APP_IMAGE_VERSION")

    # Nur für die lokale Entwicklung. In Produktion bleibt das aus, sonst
    # stehen Stapelspuren in der Antwort.
    debug: bool = False

    # Ablage für Dateien und SQLite; im Betrieb ein Volume.
    data_dir: Path = Path("/data")

    # Geheimnisse bekommen hier NIE einen Default. Sobald der Dienst eines
    # braucht, steht es ohne Vorgabe da:
    #
    #     api_token: SecretStr
    #
    # Fehlt der Wert dann in der Umgebung, bricht der Start mit einer klaren
    # Meldung ab — statt mit einem eingebauten "dev-secret" weiterzulaufen und
    # erst beim Kunden aufzufallen.


@lru_cache
def get_settings() -> Settings:
    """Einmal lesen, danach aus dem Zwischenspeicher.

    In Tests, die andere Werte brauchen, ``get_settings.cache_clear()`` rufen.
    """
    return Settings()
