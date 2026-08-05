"""Testes das series por dia e por conversa que alimentam a aba de analise."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

import pytest

from kiro_eye_monitor.models import TurnRecord
from kiro_eye_monitor.timeline import TITULO_AUSENTE, credits_by_chat, credits_by_day

SAO_PAULO = timezone(timedelta(hours=-3))


def _em_sao_paulo(momento: datetime) -> datetime:
    """Conversor de horario usado no lugar do fuso da maquina que roda o teste."""
    return momento.astimezone(SAO_PAULO)


def _turno(
    creditos: float,
    quando: datetime,
    sessao: str = "s1",
    titulo: str = "arrumar o build",
    projeto: str = "/home/dev/nav",
) -> TurnRecord:
    return TurnRecord(
        session_id=sessao,
        session_title=titulo,
        project_path=projeto,
        model="claude-opus-5",
        credits=creditos,
        ended_at=quando,
        duration_seconds=1.5,
        end_reason="Success",
    )


def test_soma_os_creditos_de_cada_dia() -> None:
    turnos = [
        _turno(1.5, datetime(2026, 7, 20, 13, tzinfo=timezone.utc)),
        _turno(2.0, datetime(2026, 7, 20, 18, tzinfo=timezone.utc)),
        _turno(4.0, datetime(2026, 7, 21, 13, tzinfo=timezone.utc)),
    ]

    dias = credits_by_day(turnos, _em_sao_paulo)

    assert [(d.day, d.credits, d.turn_count) for d in dias] == [
        (date(2026, 7, 21), pytest.approx(4.0), 1),
        (date(2026, 7, 20), pytest.approx(3.5), 2),
    ]


def test_ordena_do_dia_mais_recente_para_o_mais_antigo() -> None:
    turnos = [
        _turno(1.0, datetime(2026, 7, 10, 12, tzinfo=timezone.utc)),
        _turno(1.0, datetime(2026, 7, 28, 12, tzinfo=timezone.utc)),
        _turno(1.0, datetime(2026, 7, 19, 12, tzinfo=timezone.utc)),
    ]

    assert [d.day.day for d in credits_by_day(turnos, _em_sao_paulo)] == [28, 19, 10]


def test_turno_da_noite_conta_no_dia_local_e_nao_no_utc() -> None:
    """22h de Sao Paulo e o dia seguinte em UTC; a janela mostra o dia do dev."""
    noite = _turno(3.0, datetime(2026, 7, 21, 1, 30, tzinfo=timezone.utc))

    dias = credits_by_day([noite], _em_sao_paulo)

    assert [d.day for d in dias] == [date(2026, 7, 20)]


def test_conta_quantas_conversas_houve_no_dia() -> None:
    turnos = [
        _turno(1.0, datetime(2026, 7, 20, 12, tzinfo=timezone.utc), sessao="a"),
        _turno(1.0, datetime(2026, 7, 20, 13, tzinfo=timezone.utc), sessao="a"),
        _turno(1.0, datetime(2026, 7, 20, 14, tzinfo=timezone.utc), sessao="b"),
    ]

    assert credits_by_day(turnos, _em_sao_paulo)[0].chat_count == 2


def test_sem_turnos_nao_ha_dia() -> None:
    assert credits_by_day([], _em_sao_paulo) == ()


def test_agrupa_conversas_da_mais_cara_para_a_mais_barata() -> None:
    turnos = [
        _turno(1.0, datetime(2026, 7, 20, 12, tzinfo=timezone.utc), sessao="barata"),
        _turno(5.0, datetime(2026, 7, 20, 13, tzinfo=timezone.utc), sessao="cara"),
        _turno(3.0, datetime(2026, 7, 20, 14, tzinfo=timezone.utc), sessao="cara"),
    ]

    chats = credits_by_chat(turnos)

    assert [(c.session_id, c.credits, c.turn_count) for c in chats] == [
        ("cara", pytest.approx(8.0), 2),
        ("barata", pytest.approx(1.0), 1),
    ]


def test_conversa_guarda_titulo_e_projeto() -> None:
    turno = _turno(
        1.0,
        datetime(2026, 7, 20, 12, tzinfo=timezone.utc),
        titulo="revisar o parser do /usage",
        projeto="/home/dev/loja-online",
    )

    chat = credits_by_chat([turno])[0]

    assert chat.title == "revisar o parser do /usage"
    assert chat.project_path == "/home/dev/loja-online"


def test_conversa_sem_titulo_recebe_rotulo_proprio() -> None:
    turno = _turno(1.0, datetime(2026, 7, 20, 12, tzinfo=timezone.utc), titulo="")

    assert credits_by_chat([turno])[0].title == TITULO_AUSENTE


def test_conversa_registra_o_primeiro_e_o_ultimo_turno() -> None:
    primeiro = datetime(2026, 7, 20, 12, tzinfo=timezone.utc)
    ultimo = datetime(2026, 7, 22, 9, tzinfo=timezone.utc)
    turnos = [_turno(1.0, ultimo), _turno(1.0, primeiro)]

    chat = credits_by_chat(turnos)[0]

    assert (chat.first_turn_at, chat.last_turn_at) == (primeiro, ultimo)


def test_empate_de_creditos_entre_conversas_ordena_por_titulo() -> None:
    turnos = [
        _turno(1.0, datetime(2026, 7, 20, 12, tzinfo=timezone.utc), sessao="z", titulo="zebra"),
        _turno(1.0, datetime(2026, 7, 20, 13, tzinfo=timezone.utc), sessao="a", titulo="abelha"),
    ]

    assert [c.title for c in credits_by_chat(turnos)] == ["abelha", "zebra"]


def test_sem_turnos_nao_ha_conversa() -> None:
    assert credits_by_chat([]) == ()
