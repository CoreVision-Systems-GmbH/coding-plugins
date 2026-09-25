| Zweck                                   | Befehl                                            |
| --------------------------------------- | ------------------------------------------------- |
| Alles prüfen (shellcheck, ruff, pytest) | `bash scripts/check.sh`                           |
| Shell-Skripte prüfen                    | `shellcheck scripts/*.sh tests/*.sh`              |
| Python prüfen                           | `ruff format --check . && ruff check .`           |
| Tests                                   | `pytest -q` und `bash tests/test_beispiel_sh.sh`  |
| Ein Werkzeug ausprobieren               | `bash scripts/beispiel.sh --dry-run`              |
| Hilfe eines Werkzeugs                   | `bash scripts/beispiel.sh --help`                 |

`scripts/check.sh` prüft, was es im Repo gibt (auch die Shell-Tests unter `tests/`), und endet
rot, wenn ein Werkzeug fehlt (`pip install shellcheck-py ruff pytest`); die CI führt denselben
Befehl aus. Es gibt kein Abbild und keinen Verbund: Geliefert wird der Tarball eines Tags
`vX.Y.Z` oder ein `git checkout <tag>` auf dem Zielsystem.
