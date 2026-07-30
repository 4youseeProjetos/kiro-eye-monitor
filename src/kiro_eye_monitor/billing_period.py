"""Limites do ciclo de faturamento.

O ``/usage`` informa apenas quando o ciclo reseta. Como o credito e mensal, o
inicio do ciclo corrente e um mes antes desse reset — e esse recorte que faz a
soma da fonte B ser comparavel com o total da fonte A.
"""

from __future__ import annotations

from calendar import monthrange
from datetime import date, datetime, time, timezone

_MONTHS_IN_YEAR = 12


def period_start_from_reset(resets_on: date) -> date:
    """Inicio do ciclo mensal que termina em ``resets_on``.

    >>> period_start_from_reset(date(2026, 8, 1))
    datetime.date(2026, 7, 1)
    >>> period_start_from_reset(date(2026, 1, 15))
    datetime.date(2025, 12, 15)
    """
    year, month = _previous_month(resets_on.year, resets_on.month)
    return date(year, month, min(resets_on.day, monthrange(year, month)[1]))


def start_of_day_utc(day: date) -> datetime:
    """Meia-noite UTC de ``day``, usado para filtrar turnos do ciclo."""
    return datetime.combine(day, time.min, tzinfo=timezone.utc)


def _previous_month(year: int, month: int) -> tuple[int, int]:
    """Par (ano, mes) imediatamente anterior a ``(year, month)``."""
    if month == 1:
        return year - 1, _MONTHS_IN_YEAR
    return year, month - 1
