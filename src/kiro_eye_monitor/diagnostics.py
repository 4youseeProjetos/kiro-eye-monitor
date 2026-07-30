"""Retrato do ambiente da distro, anexado a cada falha registrada.

Existe para responder, sem acesso a maquina do desenvolvedor, perguntas como:
o kiro-cli esta instalado? em que caminho? o diretorio de sessoes existe e tem
arquivos? qual distro e qual python?
"""

from __future__ import annotations

import os
import platform
import shutil
import sys
from pathlib import Path


def _localizar_executavel(kiro_cli: str) -> str:
    """Caminho absoluto do kiro-cli, ou o motivo de nao ter sido achado."""
    if os.path.sep in kiro_cli:
        return kiro_cli if Path(kiro_cli).exists() else f"{kiro_cli} (inexistente)"
    encontrado = shutil.which(kiro_cli)
    return encontrado if encontrado else f"{kiro_cli} (fora do PATH)"


def _descrever_sessoes(sessions_dir: Path) -> str:
    """Estado do diretorio de sessoes: inexistente, vazio ou contagem."""
    if not sessions_dir.exists():
        return f"{sessions_dir} (inexistente)"
    quantidade = sum(1 for _ in sessions_dir.glob("*.json"))
    return f"{sessions_dir} ({quantidade} arquivos json)"


def describe_environment(kiro_cli: str, sessions_dir: Path) -> dict[str, str | int | None]:
    """Contexto do ambiente para o log de falhas.

    Exemplo:
        describe_environment("kiro-cli", Path.home() / ".kiro/sessions/cli")
    """
    return {
        "distro": os.environ.get("WSL_DISTRO_NAME") or "(fora do WSL)",
        "kernel": platform.release(),
        "python": sys.version.split()[0],
        "python_executavel": sys.executable,
        "kiro_cli": _localizar_executavel(kiro_cli),
        "sessoes": _descrever_sessoes(sessions_dir),
        "path": os.environ.get("PATH", ""),
        "home": str(Path.home()),
    }
