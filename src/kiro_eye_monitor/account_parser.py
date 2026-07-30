"""Parser da fonte A: o texto do comando ``/usage`` do kiro-cli.

Nao existe saida JSON para esse comando (verificado no kiro-cli 2.15.2), so
texto decorado com ANSI. Dois formatos ja observados:

    Estimated Usage | resets on 2026-08-01 | KIRO POWER
    Credits (2271.91 of 10000 covered in plan)
    <barra> 22%

    ... | KIRO FREE
    Monthly credits:
    <barra> 100% (resets on 01/01)
    (0.00 of 50 covered in plan)

O segundo formato (contas gratuitas, com reset em MM/DD) e suportado porque a
data pode aparecer sem ano.
"""

from __future__ import annotations

import re
from datetime import date, datetime

from kiro_eye_monitor.ansi import strip_ansi
from kiro_eye_monitor.models import AccountUsage

_CREDITS = re.compile(r"\(\s*([\d.,]+)\s+of\s+([\d.,]+)\s+covered in plan\s*\)")
_RESET_ISO = re.compile(r"resets on\s+(\d{4})-(\d{2})-(\d{2})")
_RESET_MONTH_DAY = re.compile(r"resets on\s+(\d{1,2})/(\d{1,2})")
_PERCENT = re.compile(r"(\d{1,3})\s*%")
_PLAN = re.compile(r"\bKIRO(?:\s+[A-Z+]{2,})+")
_PREVIEW_LIMIT = 300


class UsageOutputError(ValueError):
    """Output do /usage ilegivel ou incompleto."""


def parse_account_usage(raw_output: str, captured_at: datetime) -> AccountUsage:
    """Converte o output cru do ``/usage`` em :class:`AccountUsage`.

    >>> parse_account_usage(saida, datetime.now(timezone.utc)).credits_used
    2271.91
    """
    text = strip_ansi(raw_output)
    used, included = _parse_credits(text)
    return AccountUsage(
        plan_name=_parse_plan(text),
        credits_used=used,
        credits_included=included,
        used_percent=_parse_percent(text, used, included),
        resets_on=_parse_reset_date(text, captured_at.date()),
        captured_at=captured_at,
    )


def _parse_credits(text: str) -> tuple[float, float]:
    """Le o par usado/incluido da linha ``(X of Y covered in plan)``."""
    match = _CREDITS.search(text)
    if match is None:
        raise UsageOutputError(
            "linha de creditos ausente no output do /usage; esperado "
            f"'(<usado> of <cota> covered in plan)'. Recebido: {_preview(text)!r}"
        )
    return _to_float(match.group(1)), _to_float(match.group(2))


def _parse_plan(text: str) -> str:
    """Le o nome do plano (KIRO FREE, KIRO PRO, KIRO POWER...)."""
    match = _PLAN.search(text)
    if match is None:
        raise UsageOutputError(
            "nome do plano ausente no output do /usage; esperado algo como "
            f"'KIRO POWER'. Recebido: {_preview(text)!r}"
        )
    return match.group(0).strip()


def _parse_percent(text: str, used: float, included: float) -> int:
    """Le o percentual da barra; deriva de usado/cota se a barra nao vier."""
    match = _PERCENT.search(text)
    if match is not None:
        return int(match.group(1))
    if included <= 0:
        return 0
    return round(used / included * 100)


def _parse_reset_date(text: str, today: date) -> date:
    """Le a data de reset do ciclo, aceitando ISO ou MM/DD sem ano."""
    iso = _RESET_ISO.search(text)
    if iso is not None:
        return date(int(iso.group(1)), int(iso.group(2)), int(iso.group(3)))
    month_day = _RESET_MONTH_DAY.search(text)
    if month_day is None:
        raise UsageOutputError(
            "data de reset ausente no output do /usage; esperado "
            f"'resets on YYYY-MM-DD' ou 'resets on MM/DD'. Recebido: {_preview(text)!r}"
        )
    return _resolve_month_day(int(month_day.group(1)), int(month_day.group(2)), today)


def _resolve_month_day(month: int, day: int, today: date) -> date:
    """Ancora um MM/DD sem ano na proxima ocorrencia a partir de ``today``."""
    candidate = date(today.year, month, day)
    if candidate >= today:
        return candidate
    return date(today.year + 1, month, day)


def _to_float(raw: str) -> float:
    """Converte '10,000' e '2271.91' em float."""
    return float(raw.replace(",", ""))


def _preview(text: str) -> str:
    """Recorta o texto para caber em mensagem de erro sem poluir o log."""
    flat = " ".join(text.split())
    if len(flat) <= _PREVIEW_LIMIT:
        return flat
    return flat[:_PREVIEW_LIMIT] + "..."
