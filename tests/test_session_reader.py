"""Testes do leitor da fonte B, com arquivos de sessao escritos em tmp_path.

O formato replicado aqui e o observado no kiro-cli 2.15.2.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from kiro_eye_monitor.models import TurnRecord
from kiro_eye_monitor.session_reader import CliSessionReader, IdeSessionReader


def _escrever_sessao(
    sessions_dir: Path,
    session_id: str,
    cwd: str,
    turnos: list[dict[str, object]],
    title: str = "arrumar o build",
) -> None:
    """Grava um arquivo de sessao no formato do kiro-cli."""
    payload = {
        "session_id": session_id,
        "cwd": cwd,
        "title": title,
        "session_state": {"conversation_metadata": {"user_turn_metadatas": turnos}},
    }
    (sessions_dir / f"{session_id}.json").write_text(json.dumps(payload), encoding="utf-8")


def _turno(
    credits: list[float],
    end_timestamp: str | None = "2026-07-30T14:23:13.118401496Z",
    model: str | None = "claude-opus-5",
) -> dict[str, object]:
    """Um turno com N entradas de metering em creditos."""
    turno: dict[str, object] = {
        "metering_usage": [{"value": v, "unit": "credit", "unitPlural": "credits"} for v in credits],
        "model": model,
        "turn_duration": {"secs": 1, "nanos": 706771573},
        "end_reason": "Success",
    }
    if end_timestamp is not None:
        turno["end_timestamp"] = end_timestamp
    return turno


def test_le_turno_com_projeto_modelo_e_credito(tmp_path: Path) -> None:
    _escrever_sessao(tmp_path, "s1", "/home/dev/nav", [_turno([0.277186468358209])])

    turnos = CliSessionReader(tmp_path).read_turns()

    assert turnos == (
        TurnRecord(
            session_id="s1",
            session_title="arrumar o build",
            project_path="/home/dev/nav",
            model="claude-opus-5",
            credits=pytest.approx(0.277186468358209),
            ended_at=datetime(2026, 7, 30, 14, 23, 13, 118401, tzinfo=timezone.utc),
            duration_seconds=pytest.approx(1.706771573),
            end_reason="Success",
        ),
    )


def test_titulo_da_sessao_acompanha_cada_turno(tmp_path: Path) -> None:
    """O title do arquivo e o unico rotulo legivel da conversa; o id e um UUID."""
    _escrever_sessao(
        tmp_path, "s1", "/home/dev/nav", [_turno([0.5]), _turno([0.25])], title="revisar o parser"
    )

    assert {t.session_title for t in CliSessionReader(tmp_path).read_turns()} == {"revisar o parser"}


def test_titulo_ausente_vira_string_vazia(tmp_path: Path) -> None:
    _escrever_sessao(tmp_path, "s1", "/home/dev/nav", [_turno([0.5])], title="   ")

    assert CliSessionReader(tmp_path).read_turns()[0].session_title == ""


def test_soma_as_entradas_de_metering_do_mesmo_turno(tmp_path: Path) -> None:
    _escrever_sessao(tmp_path, "s1", "/home/dev/nav", [_turno([0.25, 0.5, 0.125])])

    assert CliSessionReader(tmp_path).read_turns()[0].credits == pytest.approx(0.875)


def test_ignora_metering_de_unidade_diferente_de_credito(tmp_path: Path) -> None:
    turno = _turno([0.25])
    turno["metering_usage"] = [
        {"value": 0.25, "unit": "credit"},
        {"value": 999.0, "unit": "token"},
    ]
    _escrever_sessao(tmp_path, "s1", "/home/dev/nav", [turno])

    assert CliSessionReader(tmp_path).read_turns()[0].credits == pytest.approx(0.25)


def test_descarta_turno_sem_credito(tmp_path: Path) -> None:
    _escrever_sessao(tmp_path, "s1", "/home/dev/nav", [_turno([])])

    assert CliSessionReader(tmp_path).read_turns() == ()


def test_descarta_turno_sem_horario_de_termino(tmp_path: Path) -> None:
    _escrever_sessao(tmp_path, "s1", "/home/dev/nav", [_turno([0.5], end_timestamp=None)])

    assert CliSessionReader(tmp_path).read_turns() == ()


def test_modelo_ausente_em_sessao_antiga_vira_none(tmp_path: Path) -> None:
    _escrever_sessao(tmp_path, "s1", "/home/dev/nav", [_turno([0.5], model=None)])

    assert CliSessionReader(tmp_path).read_turns()[0].model is None


def test_agrega_turnos_de_varias_sessoes(tmp_path: Path) -> None:
    _escrever_sessao(tmp_path, "s1", "/home/dev/nav", [_turno([0.5]), _turno([0.25])])
    _escrever_sessao(tmp_path, "s2", "/home/dev/outro", [_turno([1.0])])

    turnos = CliSessionReader(tmp_path).read_turns()

    assert len(turnos) == 3
    assert {t.project_path for t in turnos} == {"/home/dev/nav", "/home/dev/outro"}


def test_arquivo_corrompido_e_ignorado_sem_derrubar_a_coleta(tmp_path: Path) -> None:
    (tmp_path / "quebrado.json").write_text("{isso nao e json", encoding="utf-8")
    _escrever_sessao(tmp_path, "s1", "/home/dev/nav", [_turno([0.5])])

    assert len(CliSessionReader(tmp_path).read_turns()) == 1


def test_sessao_sem_metadata_de_conversa_nao_gera_turnos(tmp_path: Path) -> None:
    (tmp_path / "vazia.json").write_text(json.dumps({"session_id": "x"}), encoding="utf-8")

    assert CliSessionReader(tmp_path).read_turns() == ()


def test_session_id_cai_para_o_nome_do_arquivo(tmp_path: Path) -> None:
    payload = {
        "cwd": "/home/dev/nav",
        "session_state": {"conversation_metadata": {"user_turn_metadatas": [_turno([0.5])]}},
    }
    (tmp_path / "abc-123.json").write_text(json.dumps(payload), encoding="utf-8")

    assert CliSessionReader(tmp_path).read_turns()[0].session_id == "abc-123"


def test_projeto_ausente_e_rotulado_como_desconhecido(tmp_path: Path) -> None:
    payload = {
        "session_id": "s1",
        "session_state": {"conversation_metadata": {"user_turn_metadatas": [_turno([0.5])]}},
    }
    (tmp_path / "s1.json").write_text(json.dumps(payload), encoding="utf-8")

    assert CliSessionReader(tmp_path).read_turns()[0].project_path == "(desconhecido)"


def test_diretorio_inexistente_devolve_vazio(tmp_path: Path) -> None:
    assert CliSessionReader(tmp_path / "nao-existe").read_turns() == ()


def test_leitor_do_ide_nao_devolve_turnos_enquanto_o_credito_nao_e_persistido() -> None:
    assert IdeSessionReader().read_turns() == ()
