"""Testes dos limites do ciclo de faturamento."""

from __future__ import annotations

from datetime import date, datetime, timezone

from kiro_eye_monitor.billing_period import period_start_from_reset, start_of_day_utc


def test_reset_no_primeiro_dia_do_mes() -> None:
    assert period_start_from_reset(date(2026, 8, 1)) == date(2026, 7, 1)


def test_reset_em_janeiro_volta_para_dezembro_do_ano_anterior() -> None:
    assert period_start_from_reset(date(2026, 1, 15)) == date(2025, 12, 15)


def test_reset_no_meio_do_mes_preserva_o_dia() -> None:
    assert period_start_from_reset(date(2026, 7, 22)) == date(2026, 6, 22)


def test_dia_inexistente_no_mes_anterior_e_limitado_ao_ultimo_dia() -> None:
    assert period_start_from_reset(date(2026, 3, 31)) == date(2026, 2, 28)


def test_dia_limitado_respeita_ano_bissexto() -> None:
    assert period_start_from_reset(date(2028, 3, 30)) == date(2028, 2, 29)


def test_inicio_do_dia_em_utc() -> None:
    assert start_of_day_utc(date(2026, 7, 1)) == datetime(2026, 7, 1, tzinfo=timezone.utc)
