"""Ritmo de consumo medido sobre o ciclo de faturamento.

Extrapolar uma janela curta entre dois snapshots produzia numeros absurdos: 86
segundos de amostra viravam "5.259,78 creditos por dia". O ritmo que interessa
e o do mes: total consumido dividido pelo tempo ja decorrido do ciclo. Como sai
do proprio total da conta, ja fica disponivel na primeira coleta.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

from kiro_eye_monitor.billing_period import start_of_day_utc
from kiro_eye_monitor.models import AccountUsage, CyclePace

_SECONDS_PER_DAY = 86400.0
MIN_ELAPSED_DAYS = 1.0 / 24.0


def cycle_pace_from(account: AccountUsage, period_start: date, now: datetime) -> CyclePace | None:
    """Ritmo medio do ciclo e projecao ate o reset.

    Devolve ``None`` na primeira hora do ciclo, quando a amostra ainda e curta
    demais para virar media diaria.

    >>> cycle_pace_from(conta, date(2026, 7, 1), agora).credits_per_day
    80.83
    """
    decorridos = _elapsed_days(period_start, now)
    if decorridos < MIN_ELAPSED_DAYS:
        return None
    por_dia = account.credits_used / decorridos
    total = _total_days(period_start, account.resets_on)
    return CyclePace(
        period_start=period_start,
        period_end=account.resets_on,
        elapsed_days=decorridos,
        total_days=total,
        credits_per_day=por_dia,
        projected_cycle_usage=por_dia * total,
        projected_exhaustion=_exhaustion_date(account, period_start, por_dia),
    )


def _elapsed_days(period_start: date, now: datetime) -> float:
    """Dias decorridos desde o inicio do ciclo, nunca negativo."""
    segundos = (now - start_of_day_utc(period_start)).total_seconds()
    return max(0.0, segundos) / _SECONDS_PER_DAY


def _total_days(period_start: date, period_end: date) -> float:
    """Duracao do ciclo em dias."""
    return float((period_end - period_start).days)


def _exhaustion_date(account: AccountUsage, period_start: date, por_dia: float) -> date | None:
    """Dia em que a cota se esgota mantido o ritmo medio; ``None`` se nao esgota."""
    if por_dia <= 0.0:
        return None
    dias_ate_esgotar = account.credits_included / por_dia
    return period_start + timedelta(days=dias_ate_esgotar)
