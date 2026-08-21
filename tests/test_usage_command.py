"""Testes do wrapper do comando /usage.

Usa executaveis falsos em tmp_path para provar que o texto e capturado mesmo
quando sai em stderr — foi essa a causa de leituras vazias durante a
investigacao do formato.
"""

from __future__ import annotations

import stat
from pathlib import Path

import pytest

from kiro_eye_monitor.usage_agent import MinimalAgent
from kiro_eye_monitor.usage_command import KiroCliUsageCommand, UsageCommandError

_PAINEL_FALSO = 'echo "Credits (1 of 2 covered in plan)" >&2'


def _executavel_falso(tmp_path: Path, corpo: str) -> str:
    script = tmp_path / "kiro-cli-falso"
    script.write_text(f"#!/bin/sh\n{corpo}\n", encoding="utf-8")
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return str(script)


def _executavel_que_registra_chamada(tmp_path: Path, registro: Path) -> str:
    """Falso que grava cwd na primeira linha e cada argumento nas seguintes."""
    # pwd -P em vez de $PWD: subprocess troca o diretorio sem atualizar a
    # variavel de ambiente, que continuaria apontando para o cwd do teste.
    return _executavel_falso(
        tmp_path, f'printf "%s\\n" "$(pwd -P)" "$@" > "{registro}"; {_PAINEL_FALSO}'
    )


def _agente_de_teste(tmp_path: Path) -> MinimalAgent:
    agente = MinimalAgent("agente-de-teste", tmp_path / "workspace")
    agente.config_path.parent.mkdir(parents=True)
    agente.config_path.write_text("{}", encoding="utf-8")
    return agente


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


def test_agente_entra_como_argumento_e_define_o_cwd(tmp_path: Path) -> None:
    """Sem --agent e sem esse cwd, o kiro-cli carrega os MCP do usuario e trava."""
    registro = tmp_path / "chamada.txt"
    agente = _agente_de_teste(tmp_path)
    comando = _executavel_que_registra_chamada(tmp_path, registro)

    KiroCliUsageCommand(comando, agent=agente).fetch_raw()

    cwd, *argumentos = registro.read_text(encoding="utf-8").splitlines()
    assert Path(cwd) == agente.workspace.resolve()
    assert argumentos == ["chat", "--no-interactive", "--agent", "agente-de-teste", "/usage"]


def test_sem_agente_a_chamada_fica_como_antes(tmp_path: Path) -> None:
    """Fallback de instalacao sem o agente: chamada simples, sem --agent."""
    registro = tmp_path / "chamada.txt"

    KiroCliUsageCommand(_executavel_que_registra_chamada(tmp_path, registro)).fetch_raw()

    _, *argumentos = registro.read_text(encoding="utf-8").splitlines()
    assert argumentos == ["chat", "--no-interactive", "/usage"]
