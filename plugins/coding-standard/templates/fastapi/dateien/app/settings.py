"""Die eine Stelle, an der Konfiguration gelesen wird.

Jeder Wert kommt aus der Umgebung, nirgendwo sonst. Verstreute
``os.environ.get``-Aufrufe machen Konfiguration unauffindbar; deshalb steht hier
alles beisammen und der Rest der Anwendung fragt ``get_settings()``.
"""

from functools import lru_cache
from pathlib import Path
from urllib.parse import quote

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Konfiguration des Dienstes.

    Alle Schlüssel tragen den Präfix ``{{ENV_PREFIX}}`` — Ausnahmen sind die
    ausgelieferte Fassung, die aus dem Abbild kommt und dort ``APP_IMAGE_VERSION``
    heißt, und die ``DB_*``-Schlüssel, die der Datenbank-Container mitliest.
    """

    model_config = SettingsConfigDict(
        env_prefix="{{ENV_PREFIX}}",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        # Fehlt ein Pflichtwert, nennt pydantic sonst alle gelesenen Werte in der
        # Fehlermeldung — samt DB_PASSWORD im Klartext im Startprotokoll.
        hide_input_in_errors=True,
    )

    # Die ausgelieferte Fassung. Das Abbild setzt sie beim Bau; außerhalb eines
    # Containers steht hier "dev". Sichtbar in /healthz — bei einer Rückfrage
    # steht damit ohne Serverzugang fest, welcher Stand läuft.
    version: str = Field(default="dev", validation_alias="APP_IMAGE_VERSION")

    # Nur für die lokale Entwicklung. In Produktion bleibt das aus, sonst
    # stehen Stapelspuren in der Antwort.
    debug: bool = False

    # Ablage für Dateien (Uploads, Exporte); im Betrieb ein Volume.
    data_dir: Path = Path("/data")

    # Datenbank (PostgreSQL, Dienst `db` aus compose.yaml). Die Schlüssel teilt
    # sich der Dienst mit dem Datenbank-Container, deshalb ohne Präfix. Name,
    # Benutzer und Passwort haben keinen Default und dürfen nicht leer sein:
    # Fehlt einer, bricht der Start ab — nicht erst die erste Abfrage.
    db_host: str = Field(default="db", validation_alias="DB_HOST")
    db_port: int = Field(default=5432, validation_alias="DB_PORT")
    db_database: str = Field(min_length=1, validation_alias="DB_DATABASE")
    db_username: str = Field(min_length=1, validation_alias="DB_USERNAME")
    db_password: SecretStr = Field(min_length=1, validation_alias="DB_PASSWORD")

    # Geheimnisse bekommen hier NIE einen Default. Sobald der Dienst eines
    # braucht, steht es ohne Vorgabe da:
    #
    #     api_token: SecretStr
    #
    # Fehlt der Wert dann in der Umgebung, bricht der Start mit einer klaren
    # Meldung ab — statt mit einem eingebauten "dev-secret" weiterzulaufen und
    # erst beim Kunden aufzufallen.

    @property
    def database_url(self) -> str:
        """Verbindungsadresse für SQLAlchemy und Alembic (Dialekt psycopg).

        ``psycopg.connect`` selbst versteht das Schema ``postgresql+psycopg://``
        nicht — dort ``postgresql://`` nehmen. Enthält das Passwort im Klartext —
        nie loggen, nie in eine Antwort.
        Benutzer, Passwort und Name werden maskiert, damit ``@``, ``:`` oder
        ``/`` aus dem Tresor die Adresse nicht zerlegen.
        """
        benutzer = quote(self.db_username, safe="")
        passwort = quote(self.db_password.get_secret_value(), safe="")
        datenbank = quote(self.db_database, safe="")
        return (
            f"postgresql+psycopg://{benutzer}:{passwort}@{self.db_host}:{self.db_port}/{datenbank}"
        )


@lru_cache
def get_settings() -> Settings:
    """Einmal lesen, danach aus dem Zwischenspeicher.

    In Tests, die andere Werte brauchen, ``get_settings.cache_clear()`` rufen.
    """
    return Settings()
