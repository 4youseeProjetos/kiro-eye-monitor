"""Testes do agente sem MCP que o coletor usa para chamar o kiro-cli.

O que estes testes protegem: o kiro-cli inicializa os servidores MCP do agente
antes de imprimir o painel do /usage. Com um servidor remoto de OAuth, essa
espera consumia ~34s em --no-interactive e estourava o timeout de 30s do
coletor. Um MCP declarado aqui traria a falha de volta.
"""

from __future__ import annotations

import json
from pathlib import Path

from kiro_eye_monitor.usage_agent import AGENT_NAME, packaged_usage_agent


def _config_do_pacote() -> dict[str, object]:
    agente = packaged_usage_agent()
    assert agente is not None, "o agente versionado com o pacote nao foi encontrado"
    return json.loads(agente.config_path.read_text(encoding="utf-8"))


def test_agente_versionado_esta_no_pacote() -> None:
    agente = packaged_usage_agent()

    assert agente is not None
    assert agente.name == AGENT_NAME
    assert agente.config_path.is_file()


def test_agente_nao_declara_nenhum_servidor_mcp() -> None:
    """Qualquer MCP aqui devolve os 34s de espera que estouravam o timeout."""
    config = _config_do_pacote()

    assert config["mcpServers"] == {}
    assert config["useLegacyMcpJson"] is False


def test_nome_no_arquivo_bate_com_o_nome_passado_em_agent() -> None:
    """O kiro-cli resolve --agent pelo nome; divergir faz ele cair no default."""
    agente = packaged_usage_agent()

    assert agente is not None
    assert _config_do_pacote()["name"] == agente.name
    assert agente.config_path.name == f"{agente.name}.json"


def test_agente_fica_em_kiro_agents_dentro_do_workspace() -> None:
    """O kiro-cli so descobre agente de workspace nesse caminho relativo ao cwd."""
    agente = packaged_usage_agent()

    assert agente is not None
    assert agente.config_path.parent == agente.workspace / ".kiro" / "agents"


def test_pacote_sem_o_arquivo_devolve_none(tmp_path: Path) -> None:
    """Instalacao que nao carregou o dado volta ao default em vez de falhar."""
    assert packaged_usage_agent(tmp_path) is None
