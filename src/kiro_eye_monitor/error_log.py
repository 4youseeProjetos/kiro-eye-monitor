"""Registro de falhas do coletor, uma linha JSON por evento.

A janela mostra apenas a mensagem curta da falha. O diagnostico de verdade
acontece na maquina do desenvolvedor, muitas vezes por relato indireto, e por
isso cada falha e gravada com o contexto do ambiente: distro, versao do python,
onde o kiro-cli foi encontrado, quantos arquivos de sessao existem.

Formato JSON por linha para poder abrir com jq ou colar num chamado sem
depender de parser proprio.
"""

from __future__ import annotations

import json
import os
from collections.abc import Callable, Mapping
from datetime import datetime
from pathlib import Path

_LIMITE_BYTES = 512 * 1024


def default_log_path() -> Path:
    """Log em XDG state, fora do diretorio do projeto."""
    base = os.environ.get("XDG_STATE_HOME")
    raiz = Path(base) if base else Path.home() / ".local" / "state"
    return raiz / "kiro-eye-monitor" / "erros.jsonl"


class JsonlErrorLog:
    """Grava falhas em JSON por linha, com rotacao simples por tamanho.

    Exemplo:
        log = JsonlErrorLog(default_log_path(), lambda: datetime.now(timezone.utc))
        log.record("kiro-cli nao encontrado", {"distro": "Ubuntu-24.04"})
    """

    def __init__(
        self,
        path: Path,
        clock: Callable[[], datetime],
        limite_bytes: int = _LIMITE_BYTES,
    ) -> None:
        self._path = path
        self._clock = clock
        self._limite_bytes = limite_bytes

    def record(
        self,
        message: str,
        context: Mapping[str, str | int | None],
        traceback_text: str = "",
    ) -> Path:
        """Acrescenta uma falha ao log e devolve o arquivo escrito."""
        entrada: dict[str, object] = {
            "quando": self._clock().isoformat(),
            "mensagem": message,
            "ambiente": dict(context),
        }
        if traceback_text:
            entrada["traceback"] = traceback_text
        self._escrever(json.dumps(entrada, ensure_ascii=False))
        return self._path

    def _escrever(self, linha: str) -> None:
        """Escreve sem interromper a coleta: log nao pode derrubar o app."""
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            self._rotacionar_se_grande()
            with self._path.open("a", encoding="utf-8") as arquivo:
                arquivo.write(linha + "\n")
        except OSError:
            return

    def _rotacionar_se_grande(self) -> None:
        """Mantem apenas a geracao anterior, para o log nao crescer sem fim."""
        if not self._path.exists() or self._path.stat().st_size < self._limite_bytes:
            return
        anterior = self._path.with_suffix(self._path.suffix + ".1")
        anterior.unlink(missing_ok=True)
        self._path.rename(anterior)
