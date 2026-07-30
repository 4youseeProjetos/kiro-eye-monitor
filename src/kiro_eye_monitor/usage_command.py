"""Execucao do comando ``/usage`` do kiro-cli (fonte A).

O kiro-cli fica atras desta interface fina para que o resto do coletor nao
dependa de subprocess nem do formato de invocacao.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Protocol

_ARGS = ("chat", "--no-interactive", "/usage")
DEFAULT_TIMEOUT_SECONDS = 30.0


class UsageCommandError(RuntimeError):
    """O comando de usage falhou ou nao produziu texto aproveitavel."""


class AccountUsageSource(Protocol):
    """Origem do texto cru de usage da conta."""

    def fetch_raw(self) -> str:
        """Texto do /usage, ainda decorado com ANSI."""


class KiroCliUsageCommand:
    """Roda ``kiro-cli chat --no-interactive "/usage"`` e devolve o texto cru.

    >>> KiroCliUsageCommand().fetch_raw()[:16]
    '\\n\\x1b[1mEstimated Usa'
    """

    def __init__(
        self,
        executable: str = "kiro-cli",
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        cwd: Path | None = None,
    ) -> None:
        self._executable = executable
        self._timeout_seconds = timeout_seconds
        self._cwd = cwd

    def fetch_raw(self) -> str:
        completed = self._run()
        # O /usage escreve o painel em STDERR, nao em STDOUT (kiro-cli 2.15.2).
        # Ler so stdout devolve string vazia com exit code 0.
        combined = "\n".join(part for part in (completed.stderr, completed.stdout) if part)
        if not combined.strip():
            raise UsageCommandError(
                f"'{self._executable} {' '.join(_ARGS)}' terminou com codigo "
                f"{completed.returncode} sem texto em stdout nem stderr"
            )
        return combined

    def _run(self) -> subprocess.CompletedProcess[str]:
        """Invoca o binario, traduzindo falhas de ambiente em erro de dominio."""
        try:
            return subprocess.run(
                [self._executable, *_ARGS],
                capture_output=True,
                text=True,
                timeout=self._timeout_seconds,
                cwd=self._cwd,
                check=False,
            )
        except FileNotFoundError as erro:
            raise UsageCommandError(f"executavel nao encontrado: {self._executable!r}") from erro
        except subprocess.TimeoutExpired as erro:
            raise UsageCommandError(
                f"'{self._executable}' excedeu {self._timeout_seconds}s ao responder /usage"
            ) from erro
