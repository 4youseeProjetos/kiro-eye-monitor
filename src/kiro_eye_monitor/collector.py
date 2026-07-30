"""Orquestracao da coleta.

Junta a fonte A (total autoritativo da conta), a fonte B (detalhe por projeto do
kiro-cli) e o ritmo do ciclo. As dependencias entram pelo construtor para que os
testes nao toquem em subprocess, disco de sessao nem relogio real.

O historico de snapshots continua sendo gravado: o ritmo exibido vem do ciclo,
mas guardar as leituras permite comparar ciclos depois.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime

from kiro_eye_monitor.account_parser import parse_account_usage
from kiro_eye_monitor.aggregator import build_cli_breakdown, unattributed_credits
from kiro_eye_monitor.billing_period import period_start_from_reset
from kiro_eye_monitor.cycle_pace import cycle_pace_from
from kiro_eye_monitor.models import AccountUsage, UsageReport, UsageSnapshot
from kiro_eye_monitor.session_reader import SessionReader
from kiro_eye_monitor.snapshot_store import SnapshotStore
from kiro_eye_monitor.usage_command import AccountUsageSource


class UsageCollector:
    """Produz um :class:`UsageReport` por ciclo de atualizacao da janela.

    >>> UsageCollector(source, reader, store, clock).collect(include_cli_detail=True)
    """

    def __init__(
        self,
        account_source: AccountUsageSource,
        session_reader: SessionReader,
        snapshot_store: SnapshotStore,
        clock: Callable[[], datetime],
    ) -> None:
        self._account_source = account_source
        self._session_reader = session_reader
        self._snapshot_store = snapshot_store
        self._clock = clock

    def collect(self, include_cli_detail: bool) -> UsageReport:
        """Le a conta e, se pedido, o detalhamento do kiro-cli desta maquina."""
        agora = self._clock()
        account = parse_account_usage(self._account_source.fetch_raw(), agora)
        self._snapshot_store.record(_snapshot_of(account))
        inicio = period_start_from_reset(account.resets_on)
        pace = cycle_pace_from(account, inicio, agora)
        if not include_cli_detail:
            return UsageReport(account, pace, None, None)
        breakdown = build_cli_breakdown(self._session_reader.read_turns(), inicio)
        return UsageReport(
            account=account,
            cycle_pace=pace,
            cli_breakdown=breakdown,
            unattributed_credits=unattributed_credits(
                account.credits_used, breakdown.total_credits
            ),
        )


def _snapshot_of(account: AccountUsage) -> UsageSnapshot:
    """Recorte persistivel da leitura da conta."""
    return UsageSnapshot(
        captured_at=account.captured_at,
        plan_name=account.plan_name,
        credits_used=account.credits_used,
        credits_included=account.credits_included,
        resets_on=account.resets_on,
    )
