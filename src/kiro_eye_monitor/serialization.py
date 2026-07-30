"""Serializacao do relatorio para JSON.

Contrato consumido pela janela do Windows. Creditos saem com duas casas porque
essa e a granularidade do medidor do Kiro (incrementos de 0.01).
"""

from __future__ import annotations

from kiro_eye_monitor.models import AccountUsage, CliBreakdown, CreditGroup, CyclePace, UsageReport

_CREDIT_DECIMALS = 2


def report_to_dict(report: UsageReport) -> dict[str, object]:
    """Converte o relatorio em estrutura pronta para ``json.dumps``."""
    return {
        "account": _account_to_dict(report.account),
        "cycle_pace": _cycle_pace_to_dict(report.cycle_pace) if report.cycle_pace else None,
        "cli_breakdown": (
            _breakdown_to_dict(report.cli_breakdown) if report.cli_breakdown else None
        ),
        "unattributed_credits": _round(report.unattributed_credits),
    }


def _account_to_dict(account: AccountUsage) -> dict[str, object]:
    return {
        "plan_name": account.plan_name,
        "credits_used": _round(account.credits_used),
        "credits_included": _round(account.credits_included),
        "credits_remaining": _round(account.credits_remaining),
        "used_percent": account.used_percent,
        "resets_on": account.resets_on.isoformat(),
        "captured_at": account.captured_at.isoformat(),
    }


def _breakdown_to_dict(breakdown: CliBreakdown) -> dict[str, object]:
    return {
        "period_start": breakdown.period_start.isoformat(),
        "total_credits": _round(breakdown.total_credits),
        "turn_count": breakdown.turn_count,
        "by_project": [_group_to_dict(group) for group in breakdown.by_project],
        "by_model": [_group_to_dict(group) for group in breakdown.by_model],
    }


def _cycle_pace_to_dict(pace: CyclePace) -> dict[str, object]:
    esgotamento = pace.projected_exhaustion
    return {
        "period_start": pace.period_start.isoformat(),
        "period_end": pace.period_end.isoformat(),
        "elapsed_days": round(pace.elapsed_days, 2),
        "total_days": pace.total_days,
        "remaining_days": round(pace.remaining_days, 2),
        "credits_per_day": _round(pace.credits_per_day),
        "projected_cycle_usage": _round(pace.projected_cycle_usage),
        "projected_exhaustion": esgotamento.isoformat() if esgotamento else None,
        "exhausts_before_reset": pace.exhausts_before_reset,
    }


def _group_to_dict(group: CreditGroup) -> dict[str, object]:
    return {
        "label": group.label,
        "credits": _round(group.credits),
        "turn_count": group.turn_count,
    }


def _round(value: float | None) -> float | None:
    """Arredonda para a casa do medidor do Kiro, preservando ausencia."""
    if value is None:
        return None
    return round(value, _CREDIT_DECIMALS)
