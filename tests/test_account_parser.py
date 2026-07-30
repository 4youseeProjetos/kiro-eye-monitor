"""Testes do parser da fonte A (/usage), incluindo o output real capturado."""

from __future__ import annotations

from datetime import date, datetime, timezone
from pathlib import Path

import pytest

from kiro_eye_monitor.account_parser import UsageOutputError, parse_account_usage

FIXTURES = Path(__file__).parent / "fixtures"
AGORA = datetime(2026, 7, 30, 15, 0, tzinfo=timezone.utc)


def _fixture(nome: str) -> str:
    return (FIXTURES / nome).read_text(encoding="utf-8")


def test_plano_pago_com_reset_iso() -> None:
    usage = parse_account_usage(_fixture("usage_paid_plan.txt"), AGORA)

    assert usage.plan_name == "KIRO PRO"
    assert usage.credits_used == pytest.approx(1234.56)
    assert usage.credits_included == pytest.approx(5000.0)
    assert usage.used_percent == 25
    assert usage.resets_on == date(2026, 8, 1)
    assert usage.captured_at == AGORA


def test_saldo_restante_derivado_do_total() -> None:
    usage = parse_account_usage(_fixture("usage_paid_plan.txt"), AGORA)

    assert usage.credits_remaining == pytest.approx(3765.44)


def test_saldo_restante_nunca_negativo_em_overage() -> None:
    usage = parse_account_usage("KIRO PRO (120 of 100 covered in plan) resets on 2026-09-01", AGORA)

    assert usage.credits_remaining == 0.0


def test_plano_gratuito_com_reset_em_mes_dia() -> None:
    usage = parse_account_usage(_fixture("usage_free_plan.txt"), AGORA)

    assert usage.plan_name == "KIRO FREE"
    assert usage.credits_used == pytest.approx(0.0)
    assert usage.credits_included == pytest.approx(50.0)
    assert usage.resets_on == date(2027, 1, 1), "01/01 ja passou em 2026, ancora no ano seguinte"


def test_reset_em_mes_dia_futuro_fica_no_ano_corrente() -> None:
    texto = "KIRO FREE 10% (resets on 12/25) (5.00 of 50 covered in plan)"

    assert parse_account_usage(texto, AGORA).resets_on == date(2026, 12, 25)


def test_percentual_derivado_quando_a_barra_nao_vem() -> None:
    texto = "KIRO PRO resets on 2026-08-01 (25.00 of 100 covered in plan)"

    assert parse_account_usage(texto, AGORA).used_percent == 25


def test_cota_com_separador_de_milhar() -> None:
    texto = "KIRO POWER resets on 2026-08-01 (1,234.50 of 10,000 covered in plan)"
    usage = parse_account_usage(texto, AGORA)

    assert usage.credits_used == pytest.approx(1234.50)
    assert usage.credits_included == pytest.approx(10000.0)


def test_erro_cita_o_texto_recebido_quando_falta_linha_de_creditos() -> None:
    with pytest.raises(UsageOutputError) as erro:
        parse_account_usage("KIRO POWER resets on 2026-08-01", AGORA)

    assert "covered in plan" in str(erro.value)
    assert "KIRO POWER resets on 2026-08-01" in str(erro.value)


def test_erro_quando_falta_nome_do_plano() -> None:
    with pytest.raises(UsageOutputError, match="nome do plano ausente"):
        parse_account_usage("resets on 2026-08-01 (1 of 2 covered in plan)", AGORA)


def test_erro_quando_falta_data_de_reset() -> None:
    with pytest.raises(UsageOutputError, match="data de reset ausente"):
        parse_account_usage("KIRO POWER (1 of 2 covered in plan)", AGORA)
