"""Agente minimo com que o coletor chama o kiro-cli, para nao carregar MCP.

O painel do ``/usage`` e resolvido localmente e nao precisa de ferramenta
nenhuma, mas o kiro-cli inicializa os servidores MCP do agente default antes de
imprimir qualquer coisa. Servidor remoto que exige OAuth (o do Atlassian, por
exemplo) nunca conclui em ``--no-interactive``: o processo espera a janela
inteira de ``mcp.noInteractiveTimeout`` e so entao imprime. Medido nesta
maquina com kiro-cli 2.18.1: 34s parado contra 2s com este agente, o que
estourava o timeout de 30s do coletor.

O kiro-cli descobre agente de workspace em ``<cwd>/.kiro/agents/*.json`` e nao
aceita caminho de arquivo em ``--agent`` (responde "no agent with name ...
found" e cai no default). Por isso o agente vem com o pacote e o comando roda
com cwd na pasta que o contem.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

AGENT_NAME = "kiro-eye-monitor-usage"
_WORKSPACE_DIRNAME = "agent_workspace"


@dataclass(frozen=True)
class MinimalAgent:
    """Agente sem MCP: o nome para ``--agent`` e o cwd que o torna visivel."""

    name: str
    workspace: Path

    @property
    def config_path(self) -> Path:
        """Arquivo de configuracao lido pelo kiro-cli."""
        return self.workspace / ".kiro" / "agents" / f"{self.name}.json"


def packaged_usage_agent(package_dir: Path | None = None) -> MinimalAgent | None:
    """Agente versionado com o pacote, ou ``None`` se o arquivo nao veio.

    Devolver ``None`` em vez de falhar mantem a coleta funcionando quando o
    pacote e instalado sem esse dado: volta-se ao agente default do usuario,
    que e lento por causa do MCP, mas ainda produz o painel.

    Exemplo:
        agente = packaged_usage_agent()
        args = ["--agent", agente.name] if agente else []
    """
    raiz = package_dir if package_dir is not None else Path(__file__).parent
    agente = MinimalAgent(AGENT_NAME, raiz / _WORKSPACE_DIRNAME)
    return agente if agente.config_path.is_file() else None
