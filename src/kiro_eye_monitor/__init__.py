"""Coletor de consumo de creditos Kiro (fonte A: conta; fonte B: sessoes locais).

``__version__`` e a fonte unica da versao do projeto: o pyproject a le daqui, o
install.sh a grava junto da janela instalada e o coletor a devolve no JSON. E
assim que a janela descobre que esta rodando com um coletor de outra versao —
o caso de quem fez ``git pull`` sem rodar o ``install.sh`` de novo.
"""

__version__ = "0.2.0"
