"""Testes do registro de falhas em JSON por linha."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from kiro_eye_monitor.error_log import JsonlErrorLog, default_log_path

_QUANDO = datetime(2026, 7, 30, 18, 5, tzinfo=timezone.utc)


def _log(path: Path, limite_bytes: int = 512 * 1024) -> JsonlErrorLog:
    return JsonlErrorLog(path, lambda: _QUANDO, limite_bytes)


def test_grava_uma_linha_json_por_falha(tmp_path: Path) -> None:
    destino = tmp_path / "erros.jsonl"
    _log(destino).record("kiro-cli nao encontrado", {"distro": "Ubuntu-24.04"})

    linhas = destino.read_text(encoding="utf-8").splitlines()
    assert len(linhas) == 1
    entrada = json.loads(linhas[0])
    assert entrada["mensagem"] == "kiro-cli nao encontrado"
    assert entrada["ambiente"]["distro"] == "Ubuntu-24.04"
    assert entrada["quando"] == "2026-07-30T18:05:00+00:00"


def test_acrescenta_sem_apagar_o_anterior(tmp_path: Path) -> None:
    destino = tmp_path / "erros.jsonl"
    log = _log(destino)
    log.record("primeira", {})
    log.record("segunda", {})

    linhas = destino.read_text(encoding="utf-8").splitlines()
    assert [json.loads(linha)["mensagem"] for linha in linhas] == ["primeira", "segunda"]


def test_inclui_traceback_quando_informado(tmp_path: Path) -> None:
    destino = tmp_path / "erros.jsonl"
    _log(destino).record("falhou", {}, traceback_text="Traceback...\nValueError")

    entrada = json.loads(destino.read_text(encoding="utf-8"))
    assert "ValueError" in entrada["traceback"]


def test_omite_traceback_vazio(tmp_path: Path) -> None:
    destino = tmp_path / "erros.jsonl"
    _log(destino).record("falhou", {})

    assert "traceback" not in json.loads(destino.read_text(encoding="utf-8"))


def test_cria_o_diretorio_do_log(tmp_path: Path) -> None:
    destino = tmp_path / "fundo" / "do" / "poco" / "erros.jsonl"
    _log(destino).record("falhou", {})

    assert destino.exists()


def test_rotaciona_ao_passar_do_limite(tmp_path: Path) -> None:
    destino = tmp_path / "erros.jsonl"
    log = _log(destino, limite_bytes=200)
    for indice in range(6):
        log.record(f"falha {indice} com texto suficiente para encher o arquivo", {})

    assert destino.with_suffix(".jsonl.1").exists()
    assert destino.stat().st_size < 400


def test_nao_propaga_erro_de_escrita(tmp_path: Path) -> None:
    # Um log inacessivel nao pode impedir a coleta de responder.
    ocupado = tmp_path / "arquivo"
    ocupado.write_text("nao sou diretorio", encoding="utf-8")

    _log(ocupado / "erros.jsonl").record("falhou", {})


def test_caminho_padrao_respeita_xdg_state_home(monkeypatch) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", "/tmp/estado")

    assert default_log_path() == Path("/tmp/estado/kiro-eye-monitor/erros.jsonl")


def test_caminho_padrao_sem_xdg_usa_local_state(monkeypatch) -> None:
    monkeypatch.delenv("XDG_STATE_HOME", raising=False)
    monkeypatch.setattr(Path, "home", classmethod(lambda _: Path("/home/dev")))

    assert default_log_path() == Path("/home/dev/.local/state/kiro-eye-monitor/erros.jsonl")
