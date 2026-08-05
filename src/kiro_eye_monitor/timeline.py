"""Series de consumo por dia e por conversa, para a aba de analise da janela.

O resumo por projeto responde "onde" o credito foi gasto. Estas duas series
respondem "quando" e "em qual conversa", que e o que permite ao desenvolvedor
ligar um pico de consumo a um dia de trabalho ou a um chat especifico.

A unidade continua sendo credito: os arquivos de sessao trazem
``input_token_count`` e ``output_token_count`` zerados, entao nao existe serie de
token para montar.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Callable, Sequence
from datetime import date, datetime

from kiro_eye_monitor.models import ChatCredits, DailyCredits, TurnRecord

TITULO_AUSENTE = "(sem titulo)"

# Converte o horario UTC do turno para o fuso de quem le a janela.
LocalTime = Callable[[datetime], datetime]


def credits_by_day(turns: Sequence[TurnRecord], local_time: LocalTime) -> tuple[DailyCredits, ...]:
    """Consumo por dia do calendario local, do dia mais recente para o mais antigo.

    O dia e o local, e nao o UTC: um turno das 22h em Sao Paulo cai no dia
    seguinte em UTC, e quem olha "ontem" na janela quer o ontem dele.

    >>> credits_by_day(turns, lambda t: t.astimezone())[0].day
    datetime.date(2026, 7, 30)
    """
    por_dia: dict[date, list[TurnRecord]] = defaultdict(list)
    for turn in turns:
        por_dia[local_time(turn.ended_at).date()].append(turn)
    dias = [_daily_credits(dia, do_dia) for dia, do_dia in por_dia.items()]
    return tuple(sorted(dias, key=lambda dia: dia.day, reverse=True))


def credits_by_chat(turns: Sequence[TurnRecord]) -> tuple[ChatCredits, ...]:
    """Consumo por conversa, da mais cara para a mais barata.

    Ordenado por credito, e nao por data, porque a pergunta da aba e "qual chat
    consumiu mais"; a data de cada conversa vai em ``last_turn_at``.

    >>> credits_by_chat(turns)[0].turn_count
    19
    """
    por_chat: dict[str, list[TurnRecord]] = defaultdict(list)
    for turn in turns:
        por_chat[turn.session_id].append(turn)
    chats = [_chat_credits(session_id, do_chat) for session_id, do_chat in por_chat.items()]
    return tuple(sorted(chats, key=lambda chat: (-chat.credits, chat.title)))


def _daily_credits(day: date, turns: Sequence[TurnRecord]) -> DailyCredits:
    """Totais de um dia ja separado."""
    return DailyCredits(
        day=day,
        credits=sum(turn.credits for turn in turns),
        turn_count=len(turns),
        chat_count=len({turn.session_id for turn in turns}),
    )


def _chat_credits(session_id: str, turns: Sequence[TurnRecord]) -> ChatCredits:
    """Totais de uma conversa ja separada, com a janela de tempo que ela ocupou."""
    ordenados = sorted(turns, key=lambda turn: turn.ended_at)
    return ChatCredits(
        session_id=session_id,
        title=ordenados[0].session_title or TITULO_AUSENTE,
        project_path=ordenados[0].project_path,
        credits=sum(turn.credits for turn in turns),
        turn_count=len(turns),
        first_turn_at=ordenados[0].ended_at,
        last_turn_at=ordenados[-1].ended_at,
    )
