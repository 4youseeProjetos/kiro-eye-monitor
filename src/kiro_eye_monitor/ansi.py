"""Limpeza das sequencias de escape ANSI emitidas pelo kiro-cli.

O comando /usage pinta plano, barra e dicas com SGR (\\x1b[38;5;141m), move o
cursor (\\x1b[1G) e alterna visibilidade (\\x1b[?25h). Nada disso interessa ao
parser, e a barra de progresso vira ruido se as cores nao sairem antes.
"""

from __future__ import annotations

import re

_ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")


def strip_ansi(text: str) -> str:
    """Remove todas as sequencias de escape ANSI de ``text``.

    >>> strip_ansi("\\x1b[1mCredits\\x1b[0m (10 of 50 covered in plan)")
    'Credits (10 of 50 covered in plan)'
    """
    return _ANSI_ESCAPE.sub("", text)
