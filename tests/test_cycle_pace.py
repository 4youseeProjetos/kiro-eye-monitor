"""Testes do ritmo de consumo medido sobre o ciclo de faturamento."""

from __future__ import annotations

from datetime import date, datetime, timezone

import pytest

from kiro_eye_monitor.cycle_pace import cycle_pace_from
from kiro_eye_monitor.models import AccountUsage

INICIO = date(2026, 7, 1)
RESET = date(2026, 8, 1)


def _conta(usados: float, cota: float = 10000.0, reset: date = RESET) -> AccountUsage:
    return AccountUsage(
        plan_name="KIRO POWER",
        credits_used=usados,
        credits_included=cota,
        used_percent=int(usados / cota * 100),
        resets_on=reset,
        captured_at=datetime(2026, 7, 30, 12, tzinfo=timezone.utc),
    )


def test_media_diaria_do_ciclo() -> None:
    # 10 dias decorridos, 1000 creditos -> 100 por dia.
    agora = datetime(2026, 7, 11, tzinfo=timezone.utc)

    pace = cycle_pace_from(_conta(1000.0), INICIO, agora)

    assert pace is not None
    assert pace.elapsed_days == pytest.approx(10.0)
    assert pace.credits_per_day == pytest.approx(100.0)


def test_duracao_e_dias_restantes_do_ciclo() -> None:
    agora = datetime(2026, 7, 11, tzinfo=timezone.utc)

    pace = cycle_pace_from(_conta(1000.0), INICIO, agora)

    assert pace is not None
    assert pace.total_days == pytest.approx(31.0)
    assert pace.remaining_days == pytest.approx(21.0)


def test_projecao_do_consumo_no_fim_do_ciclo() -> None:
    agora = datetime(2026, 7, 11, tzinfo=timezone.utc)

    pace = cycle_pace_from(_conta(1000.0), INICIO, agora)

    assert pace is not None
    assert pace.projected_cycle_usage == pytest.approx(3100.0)


def test_meio_dia_decorrido_conta_como_fracao() -> None:
    agora = datetime(2026, 7, 1, 12, tzinfo=timezone.utc)

    pace = cycle_pace_from(_conta(50.0), INICIO, agora)

    assert pace is not None
    assert pace.elapsed_days == pytest.approx(0.5)
    assert pace.credits_per_day == pytest.approx(100.0)


def test_primeira_hora_do_ciclo_nao_gera_media() -> None:
    agora = datetime(2026, 7, 1, 0, 30, tzinfo=timezone.utc)

    assert cycle_pace_from(_conta(5.0), INICIO, agora) is None


def test_ritmo_que_estoura_a_cota_antes_do_reset() -> None:
    # 500 por dia com cota de 10000 esgota em 20 dias, antes de 01/08.
    agora = datetime(2026, 7, 11, tzinfo=timezone.utc)

    pace = cycle_pace_from(_conta(5000.0), INICIO, agora)

    assert pace is not None
    assert pace.projected_exhaustion == date(2026, 7, 21)
    assert pace.exhausts_before_reset is True


def test_ritmo_que_nao_estoura_a_cota() -> None:
    agora = datetime(2026, 7, 11, tzinfo=timezone.utc)

    pace = cycle_pace_from(_conta(1000.0), INICIO, agora)

    assert pace is not None
    assert pace.exhausts_before_reset is False


def test_sem_consumo_nao_ha_data_de_esgotamento() -> None:
    agora = datetime(2026, 7, 11, tzinfo=timezone.utc)

    pace = cycle_pace_from(_conta(0.0), INICIO, agora)

    assert pace is not None
    assert pace.credits_per_day == pytest.approx(0.0)
    assert pace.projected_exhaustion is None
    assert pace.exhausts_before_reset is False


def test_ciclo_de_fevereiro_tem_duracao_menor() -> None:
    pace = cycle_pace_from(
        _conta(280.0, reset=date(2026, 3, 1)),
        date(2026, 2, 1),
        datetime(2026, 2, 15, tzinfo=timezone.utc),
    )

    assert pace is not None
    assert pace.total_days == pytest.approx(28.0)
    assert pace.credits_per_day == pytest.approx(20.0)
