"""Agregacao dos turnos da fonte B em totais por projeto e por modelo.

A fonte B cobre apenas o kiro-cli desta maquina. A diferenca entre o total da
conta (fonte A) e essa soma e exposta como credito nao atribuido, em vez de
escondida: hoje ela representa cerca de um terco do consumo real (IDE, web,
outra maquina ou sessoes apagadas).
"""

from __future__ import annotations

from collections import Counter, defaultdict
from collections.abc import Callable, Sequence
from datetime import date

from kiro_eye_monitor.billing_period import start_of_day_utc
from kiro_eye_monitor.models import CliBreakdown, CreditGroup, TurnRecord

MODELO_NAO_INFORMADO = "(nao informado)"


def build_cli_breakdown(turns: Sequence[TurnRecord], period_start: date) -> CliBreakdown:
    """Soma os turnos do ciclo corrente e agrupa por projeto e por modelo.

    >>> build_cli_breakdown(turns, date(2026, 7, 1)).by_project[0].label
    '/home/dev/loja-online'
    """
    limite = start_of_day_utc(period_start)
    do_ciclo = tuple(turn for turn in turns if turn.ended_at >= limite)
    return CliBreakdown(
        period_start=period_start,
        total_credits=sum(turn.credits for turn in do_ciclo),
        turn_count=len(do_ciclo),
        by_project=_group(do_ciclo, lambda turn: turn.project_path),
        by_model=_group(do_ciclo, lambda turn: turn.model or MODELO_NAO_INFORMADO),
    )


def unattributed_credits(account_credits_used: float, cli_credits: float) -> float:
    """Parte do total da conta que a fonte B nao explica, nunca negativa.

    Fica negativa apenas por defasagem de atualizacao (o total da conta e
    atualizado a cada ~5 minutos, os arquivos de sessao na hora), e nesse caso
    zero e a leitura honesta.
    """
    return max(0.0, account_credits_used - cli_credits)


def _group(
    turns: Sequence[TurnRecord],
    label_of: Callable[[TurnRecord], str],
) -> tuple[CreditGroup, ...]:
    """Agrupa por rotulo, ordenando do maior consumo para o menor."""
    credits: dict[str, float] = defaultdict(float)
    counts: Counter[str] = Counter()
    for turn in turns:
        label = label_of(turn)
        credits[label] += turn.credits
        counts[label] += 1
    groups = [CreditGroup(label, total, counts[label]) for label, total in credits.items()]
    return tuple(sorted(groups, key=lambda group: (-group.credits, group.label)))
