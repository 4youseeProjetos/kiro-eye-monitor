"""Testes do strip de ANSI contra as sequencias que o kiro-cli realmente emite."""

from __future__ import annotations

from pathlib import Path

from kiro_eye_monitor.ansi import strip_ansi

FIXTURES = Path(__file__).parent / "fixtures"


def test_remove_cores_sgr() -> None:
    assert strip_ansi("\x1b[1mCredits\x1b[0m (10 of 50)") == "Credits (10 of 50)"


def test_remove_cor_estendida_256() -> None:
    assert strip_ansi("\x1b[38;5;141mKIRO POWER\x1b[0m") == "KIRO POWER"


def test_remove_movimento_de_cursor_e_visibilidade() -> None:
    assert strip_ansi("fim\x1b[1G\x1b[?25h") == "fim"


def test_texto_sem_escape_fica_intacto() -> None:
    assert strip_ansi("Credits (0.00 of 50 covered in plan)") == (
        "Credits (0.00 of 50 covered in plan)"
    )


def test_output_real_nao_sobra_nenhum_escape() -> None:
    raw = (FIXTURES / "usage_paid_plan.txt").read_text(encoding="utf-8")
    assert "\x1b" in raw, "fixture deveria conter ANSI cru"
    assert "\x1b" not in strip_ansi(raw)
