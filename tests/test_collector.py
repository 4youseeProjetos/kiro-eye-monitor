"""Testes do orquestrador de coleta."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import pytest

from fakes import FakeAccountUsageSource, FakeSessionReader, FrozenClock
from kiro_eye_monitor.collector import UsageCollector
from kiro_eye_monitor.models import TurnRecord
from kiro_eye_monitor.snapshot_store import SnapshotStore

USAGE = "Estimated Usage | resets on 2026-08-01 | KIRO POWER (2000.00 of 10000 covered in plan) 20%"
AGORA = datetime(2026, 7, 30, 12, tzinfo=timezone.utc)
SAO_PAULO = timezone(timedelta(hours=-3))


def _em_sao_paulo(momento: datetime) -> datetime:
    """Fuso fixo no teste para o dia local nao depender da maquina."""
    return momento.astimezone(SAO_PAULO)


def _turno(
    projeto: str,
    creditos: float,
    quando: datetime,
    sessao: str = "s1",
    titulo: str = "arrumar o build",
) -> TurnRecord:
    return TurnRecord(
        session_id=sessao,
        session_title=titulo,
        project_path=projeto,
        model="claude-opus-5",
        credits=creditos,
        ended_at=quando,
        duration_seconds=1.0,
        end_reason="Success",
    )


def _coletor(
    tmp_path: Path,
    turnos: tuple[TurnRecord, ...] = (),
    *momentos: datetime,
) -> tuple[UsageCollector, FakeSessionReader]:
    leitor = FakeSessionReader(turnos)
    coletor = UsageCollector(
        account_source=FakeAccountUsageSource(USAGE),
        session_reader=leitor,
        snapshot_store=SnapshotStore(tmp_path / "snapshots.db"),
        clock=FrozenClock(*(momentos or (AGORA,))),
        local_time=_em_sao_paulo,
    )
    return coletor, leitor


def test_relatorio_traz_o_total_da_conta(tmp_path: Path) -> None:
    coletor, _ = _coletor(tmp_path)

    relatorio = coletor.collect(include_cli_detail=False)

    assert relatorio.account.plan_name == "KIRO POWER"
    assert relatorio.account.credits_used == pytest.approx(2000.0)


def test_modo_somente_conta_nao_le_arquivos_de_sessao(tmp_path: Path) -> None:
    coletor, leitor = _coletor(tmp_path, (_turno("/a", 5.0, AGORA),))

    relatorio = coletor.collect(include_cli_detail=False)

    assert leitor.call_count == 0
    assert relatorio.cli_breakdown is None
    assert relatorio.unattributed_credits is None


def test_detalhamento_agrupa_por_projeto_no_ciclo_corrente(tmp_path: Path) -> None:
    turnos = (
        _turno("/nav", 100.0, datetime(2026, 7, 10, tzinfo=timezone.utc)),
        _turno("/manager", 50.0, datetime(2026, 7, 20, tzinfo=timezone.utc)),
        _turno("/antigo", 999.0, datetime(2026, 6, 15, tzinfo=timezone.utc)),
    )
    coletor, leitor = _coletor(tmp_path, turnos)

    detalhe = coletor.collect(include_cli_detail=True).cli_breakdown

    assert leitor.call_count == 1
    assert detalhe is not None
    assert detalhe.period_start == date(2026, 7, 1)
    assert detalhe.total_credits == pytest.approx(150.0)
    assert [g.label for g in detalhe.by_project] == ["/nav", "/manager"]


def test_detalhamento_traz_a_serie_por_dia_local(tmp_path: Path) -> None:
    """22h em Sao Paulo e madrugada do dia seguinte em UTC; vale o dia do dev."""
    turnos = (
        _turno("/nav", 10.0, datetime(2026, 7, 21, 1, 30, tzinfo=timezone.utc)),
        _turno("/nav", 4.0, datetime(2026, 7, 21, 15, 0, tzinfo=timezone.utc)),
    )
    coletor, _ = _coletor(tmp_path, turnos)

    detalhe = coletor.collect(include_cli_detail=True).cli_breakdown

    assert detalhe is not None
    assert [(d.day, d.credits) for d in detalhe.by_day] == [
        (date(2026, 7, 21), pytest.approx(4.0)),
        (date(2026, 7, 20), pytest.approx(10.0)),
    ]


def test_detalhamento_traz_a_serie_por_chat(tmp_path: Path) -> None:
    turnos = (
        _turno("/nav", 10.0, datetime(2026, 7, 10, tzinfo=timezone.utc), sessao="a", titulo="parser"),
        _turno("/nav", 30.0, datetime(2026, 7, 11, tzinfo=timezone.utc), sessao="b", titulo="aba"),
    )
    coletor, _ = _coletor(tmp_path, turnos)

    detalhe = coletor.collect(include_cli_detail=True).cli_breakdown

    assert detalhe is not None
    assert [(c.title, c.credits) for c in detalhe.by_chat] == [
        ("aba", pytest.approx(30.0)),
        ("parser", pytest.approx(10.0)),
    ]


def test_nao_atribuido_e_o_que_a_fonte_b_nao_explica(tmp_path: Path) -> None:
    turnos = (_turno("/nav", 1500.0, datetime(2026, 7, 10, tzinfo=timezone.utc)),)
    coletor, _ = _coletor(tmp_path, turnos)

    relatorio = coletor.collect(include_cli_detail=True)

    assert relatorio.unattributed_credits == pytest.approx(500.0)


def test_ritmo_do_ciclo_ja_vem_na_primeira_coleta(tmp_path: Path) -> None:
    coletor, _ = _coletor(tmp_path)

    pace = coletor.collect(include_cli_detail=False).cycle_pace

    assert pace is not None
    assert pace.period_start == date(2026, 7, 1)
    assert pace.total_days == pytest.approx(31.0)
    # 2000 creditos em 29,5 dias decorridos (30/07 12:00 UTC).
    assert pace.credits_per_day == pytest.approx(2000.0 / 29.5)


def test_ritmo_ausente_na_primeira_hora_do_ciclo(tmp_path: Path) -> None:
    coletor, _ = _coletor(tmp_path, (), datetime(2026, 7, 1, 0, 20, tzinfo=timezone.utc))

    assert coletor.collect(include_cli_detail=False).cycle_pace is None


def test_cada_coleta_persiste_um_snapshot(tmp_path: Path) -> None:
    store = SnapshotStore(tmp_path / "snapshots.db")
    coletor = UsageCollector(
        account_source=FakeAccountUsageSource(USAGE),
        session_reader=FakeSessionReader(),
        snapshot_store=store,
        clock=FrozenClock(AGORA, AGORA + timedelta(hours=1)),
        local_time=_em_sao_paulo,
    )

    coletor.collect(include_cli_detail=False)
    coletor.collect(include_cli_detail=False)

    assert len(store.since(AGORA)) == 2
