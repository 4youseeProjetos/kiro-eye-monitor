"""Testes do entrypoint: contrato JSON que a janela do Windows consome."""

from __future__ import annotations

import json
import stat
from pathlib import Path

import pytest

from kiro_eye_monitor.main import main

USAGE_FALSO = 'echo "Estimated Usage | resets on 2026-08-01 | KIRO POWER" >&2; echo "Credits (2000.00 of 10000 covered in plan)" >&2; echo "bar 20%" >&2'


def _kiro_cli_falso(tmp_path: Path, corpo: str = USAGE_FALSO) -> str:
    script = tmp_path / "kiro-cli-falso"
    script.write_text(f"#!/bin/sh\n{corpo}\n", encoding="utf-8")
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return str(script)


def _sessao(sessions_dir: Path, projeto: str, creditos: float) -> None:
    sessions_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "session_id": "s1",
        "cwd": projeto,
        "session_state": {
            "conversation_metadata": {
                "user_turn_metadatas": [
                    {
                        "metering_usage": [{"value": creditos, "unit": "credit"}],
                        "model": "claude-opus-5",
                        "end_timestamp": "2026-07-15T10:00:00Z",
                        "turn_duration": {"secs": 2, "nanos": 0},
                        "end_reason": "Success",
                    }
                ]
            }
        },
    }
    (sessions_dir / "s1.json").write_text(json.dumps(payload), encoding="utf-8")


def _rodar(tmp_path: Path, capsys: pytest.CaptureFixture[str], *extra: str) -> dict[str, object]:
    codigo = main(
        [
            "--kiro-cli",
            _kiro_cli_falso(tmp_path),
            "--sessions-dir",
            str(tmp_path / "sessions"),
            "--db",
            str(tmp_path / "snapshots.db"),
            *extra,
        ]
    )
    saida = json.loads(capsys.readouterr().out)
    saida["_exit_code"] = codigo
    return saida


def test_emite_json_com_o_total_da_conta(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    saida = _rodar(tmp_path, capsys)

    assert saida["_exit_code"] == 0
    assert saida["account"] == {
        "plan_name": "KIRO POWER",
        "credits_used": 2000.0,
        "credits_included": 10000.0,
        "credits_remaining": 8000.0,
        "used_percent": 20,
        "resets_on": "2026-08-01",
        "captured_at": saida["account"]["captured_at"],
    }


def test_modo_somente_conta_omite_o_detalhamento(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    _sessao(tmp_path / "sessions", "/home/dev/nav", 300.0)

    saida = _rodar(tmp_path, capsys, "--account-only")

    assert saida["cli_breakdown"] is None
    assert saida["unattributed_credits"] is None


def test_detalhamento_traz_projeto_modelo_e_nao_atribuido(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    _sessao(tmp_path / "sessions", "/home/dev/nav", 300.0)

    saida = _rodar(tmp_path, capsys)

    assert saida["cli_breakdown"] == {
        "period_start": "2026-07-01",
        "total_credits": 300.0,
        "turn_count": 1,
        "by_project": [{"label": "/home/dev/nav", "credits": 300.0, "turn_count": 1}],
        "by_model": [{"label": "claude-opus-5", "credits": 300.0, "turn_count": 1}],
    }
    assert saida["unattributed_credits"] == 1700.0


def test_relata_o_ritmo_do_ciclo(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    pace = _rodar(tmp_path, capsys)["cycle_pace"]

    assert pace is not None
    assert pace["period_start"] == "2026-07-01"
    assert pace["period_end"] == "2026-08-01"
    assert pace["total_days"] == 31.0
    assert pace["credits_per_day"] > 0


def test_falha_do_comando_vira_json_de_erro_com_codigo_um(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    codigo = main(["--kiro-cli", _kiro_cli_falso(tmp_path, "exit 0"), "--db", str(tmp_path / "x.db")])

    saida = json.loads(capsys.readouterr().out)

    assert codigo == 1
    assert "sem texto em stdout nem stderr" in str(saida["error"])


def test_output_ilegivel_vira_json_de_erro(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    codigo = main(
        ["--kiro-cli", _kiro_cli_falso(tmp_path, 'echo "ola" >&2'), "--db", str(tmp_path / "x.db")]
    )

    saida = json.loads(capsys.readouterr().out)

    assert codigo == 1
    assert "covered in plan" in str(saida["error"])
