"""Testes do repositorio de snapshots em SQLite."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import pytest

from kiro_eye_monitor.models import UsageSnapshot
from kiro_eye_monitor.snapshot_store import SnapshotStore

BASE = datetime(2026, 7, 30, 12, tzinfo=timezone.utc)


def _snapshot(minutos: int, usados: float) -> UsageSnapshot:
    return UsageSnapshot(
        captured_at=BASE + timedelta(minutes=minutos),
        plan_name="KIRO POWER",
        credits_used=usados,
        credits_included=10000.0,
        resets_on=date(2026, 8, 1),
    )


def _store(tmp_path: Path) -> SnapshotStore:
    return SnapshotStore(tmp_path / "dados" / "snapshots.db")


def test_grava_e_le_um_snapshot(tmp_path: Path) -> None:
    store = _store(tmp_path)
    store.record(_snapshot(0, 2308.90))

    lidos = store.since(BASE)

    assert lidos == (_snapshot(0, 2308.90),)


def test_cria_o_diretorio_do_banco_na_primeira_execucao(tmp_path: Path) -> None:
    _store(tmp_path)

    assert (tmp_path / "dados" / "snapshots.db").exists()


def test_reabrir_o_store_preserva_o_historico(tmp_path: Path) -> None:
    _store(tmp_path).record(_snapshot(0, 100.0))

    assert len(_store(tmp_path).since(BASE)) == 1


def test_ordena_do_mais_antigo_para_o_mais_novo(tmp_path: Path) -> None:
    store = _store(tmp_path)
    store.record(_snapshot(30, 120.0))
    store.record(_snapshot(0, 100.0))

    assert [s.credits_used for s in store.since(BASE)] == pytest.approx([100.0, 120.0])


def test_filtra_snapshots_anteriores_ao_corte(tmp_path: Path) -> None:
    store = _store(tmp_path)
    store.record(_snapshot(0, 100.0))
    store.record(_snapshot(60, 150.0))

    assert [s.credits_used for s in store.since(BASE + timedelta(minutes=30))] == [150.0]


def test_mesmo_instante_sobrescreve_em_vez_de_duplicar(tmp_path: Path) -> None:
    store = _store(tmp_path)
    store.record(_snapshot(0, 100.0))
    store.record(_snapshot(0, 111.0))

    lidos = store.since(BASE)

    assert len(lidos) == 1
    assert lidos[0].credits_used == pytest.approx(111.0)


def test_historico_vazio_devolve_tupla_vazia(tmp_path: Path) -> None:
    assert _store(tmp_path).since(BASE) == ()
