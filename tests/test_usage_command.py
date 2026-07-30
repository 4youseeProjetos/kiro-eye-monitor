"""Testes do wrapper do comando /usage.

Usa executaveis falsos em tmp_path para provar que o texto e capturado mesmo
quando sai em stderr — foi essa a causa de leituras vazias durante a
investigacao do formato.
"""

from __future__ import annotations

import stat
from pathlib import Path

import pytest

from kiro_eye_monitor.usage_command import KiroCliUsageCommand, UsageCommandError


def _executavel_falso(tmp_path: Path, corpo: str) -> str:
    script = tmp_path / "kiro-cli-falso"
    script.write_text(f"#!/bin/sh\n{corpo}\n", encoding="utf-8")
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return str(script)


def test_captura_texto_emitido_em_stderr(tmp_path: Path) -> None:
    comando = _executavel_falso(tmp_path, 'echo "Credits (1 of 2 covered in plan)" >&2')

    assert "covered in plan" in KiroCliUsageCommand(comando).fetch_raw()


def test_captura_texto_emitido_em_stdout(tmp_path: Path) -> None:
    comando = _executavel_falso(tmp_path, 'echo "Credits (1 of 2 covered in plan)"')

    assert "covered in plan" in KiroCliUsageCommand(comando).fetch_raw()


def test_junta_os_dois_streams(tmp_path: Path) -> None:
    comando = _executavel_falso(tmp_path, 'echo "linha-err" >&2; echo "linha-out"')

    saida = KiroCliUsageCommand(comando).fetch_raw()

    assert "linha-err" in saida
    assert "linha-out" in saida


def test_saida_vazia_com_codigo_zero_e_erro_explicito(tmp_path: Path) -> None:
    comando = _executavel_falso(tmp_path, "exit 0")

    with pytest.raises(UsageCommandError, match="sem texto em stdout nem stderr"):
        KiroCliUsageCommand(comando).fetch_raw()


def test_executavel_ausente_cita_o_nome_procurado() -> None:
    with pytest.raises(UsageCommandError, match="kiro-cli-que-nao-existe"):
        KiroCliUsageCommand("kiro-cli-que-nao-existe").fetch_raw()


def test_timeout_cita_o_limite(tmp_path: Path) -> None:
    comando = _executavel_falso(tmp_path, "sleep 5")

    with pytest.raises(UsageCommandError, match="excedeu 0.2s"):
        KiroCliUsageCommand(comando, timeout_seconds=0.2).fetch_raw()
