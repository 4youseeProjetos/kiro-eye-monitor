"""Dubles nomeados usados pelos testes do coletor.

Mantidos como classes com nome proprio (em vez de stubs inline) para que a
intencao de cada duble fique legivel no teste que o usa.
"""

from __future__ import annotations

from datetime import datetime

from kiro_eye_monitor.models import TurnRecord
from kiro_eye_monitor.usage_command import UsageCommandError


class FakeAccountUsageSource:
    """Devolve um texto de /usage fixo, ou levanta o erro configurado."""

    def __init__(self, raw: str = "", error: UsageCommandError | None = None) -> None:
        self._raw = raw
        self._error = error
        self.call_count = 0

    def fetch_raw(self) -> str:
        self.call_count += 1
        if self._error is not None:
            raise self._error
        return self._raw


class FakeSessionReader:
    """Devolve turnos pre-definidos e conta quantas vezes foi lido."""

    def __init__(self, turns: tuple[TurnRecord, ...] = ()) -> None:
        self._turns = turns
        self.call_count = 0

    def read_turns(self) -> tuple[TurnRecord, ...]:
        self.call_count += 1
        return self._turns


class FrozenClock:
    """Relogio que avanca so quando o teste manda."""

    def __init__(self, *moments: datetime) -> None:
        self._moments = list(moments)

    def __call__(self) -> datetime:
        if len(self._moments) > 1:
            return self._moments.pop(0)
        return self._moments[0]
