"""Persistencia dos snapshots do total da conta.

O Kiro so expoe um acumulado do ciclo. Guardar leituras com horario e o que
permite derivar velocidade de queima e projecao — nada disso existe na origem.
"""

from __future__ import annotations

import sqlite3
from contextlib import closing
from datetime import date, datetime
from pathlib import Path

from kiro_eye_monitor.models import UsageSnapshot

_SCHEMA = """
CREATE TABLE IF NOT EXISTS snapshots (
    captured_at      TEXT PRIMARY KEY,
    plan_name        TEXT NOT NULL,
    credits_used     REAL NOT NULL,
    credits_included REAL NOT NULL,
    resets_on        TEXT NOT NULL
)
"""


class SnapshotStore:
    """Repositorio de snapshots em arquivo SQLite.

    >>> store = SnapshotStore(Path("~/.local/share/kiro-eye-monitor/snapshots.db"))
    >>> store.record(snapshot)
    """

    def __init__(self, db_path: Path) -> None:
        self._db_path = db_path
        self._prepare()

    def record(self, snapshot: UsageSnapshot) -> None:
        """Grava um snapshot; releitura no mesmo instante sobrescreve."""
        with closing(self._connect()) as connection, connection:
            connection.execute(
                "INSERT OR REPLACE INTO snapshots VALUES (?, ?, ?, ?, ?)",
                (
                    snapshot.captured_at.isoformat(),
                    snapshot.plan_name,
                    snapshot.credits_used,
                    snapshot.credits_included,
                    snapshot.resets_on.isoformat(),
                ),
            )

    def since(self, moment: datetime) -> tuple[UsageSnapshot, ...]:
        """Snapshots gravados em ``moment`` ou depois, do mais antigo ao mais novo."""
        with closing(self._connect()) as connection:
            rows = connection.execute(
                "SELECT * FROM snapshots WHERE captured_at >= ? ORDER BY captured_at",
                (moment.isoformat(),),
            ).fetchall()
        return tuple(_to_snapshot(row) for row in rows)

    def _prepare(self) -> None:
        """Cria diretorio e schema na primeira execucao."""
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        with closing(self._connect()) as connection, connection:
            connection.execute(_SCHEMA)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._db_path)
        connection.row_factory = sqlite3.Row
        return connection


def _to_snapshot(row: sqlite3.Row) -> UsageSnapshot:
    return UsageSnapshot(
        captured_at=datetime.fromisoformat(row["captured_at"]),
        plan_name=row["plan_name"],
        credits_used=row["credits_used"],
        credits_included=row["credits_included"],
        resets_on=date.fromisoformat(row["resets_on"]),
    )
