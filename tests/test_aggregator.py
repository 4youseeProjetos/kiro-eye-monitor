"""Testes da agregacao por projeto/modelo e do credito nao atribuido."""

from __future__ import annotations

from datetime import date, datetime, timezone

import pytest

from kiro_eye_monitor.aggregator import MODELO_NAO_INFORMADO, build_cli_breakdown, unattributed_credits
from kiro_eye_monitor.models import CliBreakdown, TurnRecord

CICLO = date(2026, 7, 1)


def _no_utc(momento: datetime) -> datetime:
    """Mantem o horario em UTC: o dia local nao e o assunto destes testes."""
    return momento.astimezone(timezone.utc)


def _turno(
    projeto: str,
    creditos: float,
    quando: datetime = datetime(2026, 7, 15, 12, tzinfo=timezone.utc),
    modelo: str | None = "claude-opus-5",
) -> TurnRecord:
    return TurnRecord(
        session_id="s1",
        session_title="arrumar o build",
        project_path=projeto,
        model=modelo,
        credits=creditos,
        ended_at=quando,
        duration_seconds=1.5,
        end_reason="Success",
    )


def _resumo(turnos: list[TurnRecord], ciclo: date = CICLO) -> CliBreakdown:
    return build_cli_breakdown(turnos, ciclo, _no_utc)


def test_soma_total_e_contagem_de_turnos() -> None:
    resumo = _resumo([_turno("/a", 1.5), _turno("/b", 2.0)])

    assert resumo.total_credits == pytest.approx(3.5)
    assert resumo.turn_count == 2
    assert resumo.period_start == CICLO


def test_agrupa_por_projeto_do_maior_para_o_menor() -> None:
    turnos = [_turno("/pequeno", 1.0), _turno("/grande", 5.0), _turno("/grande", 3.0)]

    grupos = _resumo(turnos).by_project

    assert [(g.label, g.credits, g.turn_count) for g in grupos] == [
        ("/grande", pytest.approx(8.0), 2),
        ("/pequeno", pytest.approx(1.0), 1),
    ]


def test_agrupa_por_modelo() -> None:
    turnos = [_turno("/a", 1.0, modelo="claude-opus-5"), _turno("/a", 4.0, modelo="auto")]

    grupos = _resumo(turnos).by_model

    assert [(g.label, g.credits) for g in grupos] == [
        ("auto", pytest.approx(4.0)),
        ("claude-opus-5", pytest.approx(1.0)),
    ]


def test_modelo_ausente_recebe_rotulo_proprio() -> None:
    grupos = _resumo([_turno("/a", 1.0, modelo=None)]).by_model

    assert grupos[0].label == MODELO_NAO_INFORMADO


def test_empate_de_creditos_ordena_por_rotulo() -> None:
    grupos = _resumo([_turno("/z", 1.0), _turno("/a", 1.0)]).by_project

    assert [g.label for g in grupos] == ["/a", "/z"]


def test_turno_anterior_ao_ciclo_e_excluido() -> None:
    antigo = _turno("/a", 9.0, quando=datetime(2026, 6, 30, 23, 59, tzinfo=timezone.utc))
    atual = _turno("/a", 1.0)

    resumo = _resumo([antigo, atual])

    assert resumo.total_credits == pytest.approx(1.0)
    assert resumo.turn_count == 1


def test_turno_na_virada_do_ciclo_entra_no_periodo() -> None:
    virada = _turno("/a", 2.0, quando=datetime(2026, 7, 1, 0, 0, tzinfo=timezone.utc))

    assert _resumo([virada]).turn_count == 1


def test_sem_turnos_o_resumo_fica_zerado() -> None:
    resumo = _resumo([])

    assert (resumo.total_credits, resumo.turn_count, resumo.by_project) == (0, 0, ())
    assert (resumo.by_day, resumo.by_chat) == ((), ())


def test_resumo_traz_a_serie_por_dia_do_ciclo() -> None:
    turnos = [
        _turno("/a", 2.0, quando=datetime(2026, 7, 15, 12, tzinfo=timezone.utc)),
        _turno("/a", 3.0, quando=datetime(2026, 7, 16, 12, tzinfo=timezone.utc)),
    ]

    dias = _resumo(turnos).by_day

    assert [(d.day, d.credits) for d in dias] == [
        (date(2026, 7, 16), pytest.approx(3.0)),
        (date(2026, 7, 15), pytest.approx(2.0)),
    ]


def test_serie_por_dia_ignora_turno_fora_do_ciclo() -> None:
    antigo = _turno("/a", 9.0, quando=datetime(2026, 6, 20, 12, tzinfo=timezone.utc))

    dias = _resumo([antigo, _turno("/a", 1.0)]).by_day

    assert [(d.day, d.credits) for d in dias] == [(date(2026, 7, 15), pytest.approx(1.0))]


def test_resumo_traz_a_serie_por_conversa() -> None:
    chats = _resumo([_turno("/a", 1.0), _turno("/a", 2.0)]).by_chat

    assert [(c.session_id, c.credits, c.turn_count) for c in chats] == [
        ("s1", pytest.approx(3.0), 2)
    ]


def test_nao_atribuido_e_a_diferenca_entre_conta_e_cli() -> None:
    assert unattributed_credits(2308.90, 1507.91) == pytest.approx(800.99)


def test_nao_atribuido_nunca_fica_negativo_por_defasagem() -> None:
    assert unattributed_credits(1500.0, 1507.91) == 0.0
