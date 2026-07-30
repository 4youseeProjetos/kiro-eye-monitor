"""Gerador do icone do app: um olho azul sobre fundo preto.

Escrito a mao em vez de usar biblioteca de imagem porque o projeto nao tem
dependencias de runtime. O formato e ICO com bitmaps de 32 bits (BGRA), que e
aceito tanto pelo Window.Icon do WPF quanto pelo System.Drawing.Icon usado no
icone de bandeja — ICO com PNG dentro tem suporte irregular no .NET Framework.

Uso: python -m kiro_eye_monitor.eye_icon windows/assets/eye.ico
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

COR_OLHO = (0, 150, 255)
COR_FUNDO = (0, 0, 0)
TAMANHOS = (16, 32, 48, 64)

_SUPERAMOSTRAGEM = 4
# Duas circunferencias deslocadas no eixo Y desenham a amendoa do olho: a
# intersecao delas tem os cantos pontudos que uma elipse nao daria.
_RAIO = 1.0955
_DESLOCAMENTO = 0.5455
_ESPESSURA = 0.11
_RAIO_IRIS = 0.30


def _dentro_da_amendoa(x: float, y: float) -> bool:
    """Ponto dentro da intersecao das duas circunferencias."""
    return (
        x * x + (y - _DESLOCAMENTO) ** 2 <= _RAIO**2
        and x * x + (y + _DESLOCAMENTO) ** 2 <= _RAIO**2
    )


def _no_contorno(x: float, y: float) -> bool:
    """Ponto sobre um dos dois arcos que formam a palpebra."""
    for centro in (_DESLOCAMENTO, -_DESLOCAMENTO):
        distancia = (x * x + (y - centro) ** 2) ** 0.5
        outro = x * x + (y + centro) ** 2
        if abs(distancia - _RAIO) <= _ESPESSURA / 2 and outro <= _RAIO**2:
            return True
    return False


def _e_traco_do_olho(x: float, y: float) -> bool:
    """Contorno da palpebra ou iris preenchida."""
    if _no_contorno(x, y):
        return True
    return (x * x + y * y) ** 0.5 <= _RAIO_IRIS and _dentro_da_amendoa(x, y)


def _cor_do_pixel(coluna: int, linha: int, tamanho: int) -> tuple[int, int, int]:
    """Cor media do pixel, superamostrada para suavizar as bordas."""
    acertos = 0
    for sub_y in range(_SUPERAMOSTRAGEM):
        for sub_x in range(_SUPERAMOSTRAGEM):
            x = ((coluna + (sub_x + 0.5) / _SUPERAMOSTRAGEM) / tamanho) * 2 - 1
            y = ((linha + (sub_y + 0.5) / _SUPERAMOSTRAGEM) / tamanho) * 2 - 1
            if _e_traco_do_olho(x, y):
                acertos += 1
    peso = acertos / (_SUPERAMOSTRAGEM**2)
    return tuple(round(COR_FUNDO[i] + (COR_OLHO[i] - COR_FUNDO[i]) * peso) for i in range(3))


def render_eye(tamanho: int) -> bytes:
    """Pixels BGRA do olho, de baixo para cima como o DIB exige.

    >>> len(render_eye(16)) == 16 * 16 * 4
    True
    """
    linhas: list[bytes] = []
    for linha in range(tamanho):
        pixels = bytearray()
        for coluna in range(tamanho):
            vermelho, verde, azul = _cor_do_pixel(coluna, linha, tamanho)
            pixels += bytes((azul, verde, vermelho, 255))
        linhas.append(bytes(pixels))
    return b"".join(reversed(linhas))


def _dib(tamanho: int) -> bytes:
    """Bitmap do icone: cabecalho, pixels e mascara AND toda opaca."""
    cabecalho = struct.pack(
        "<IiiHHIIiiII", 40, tamanho, tamanho * 2, 1, 32, 0, 0, 0, 0, 0, 0
    )
    bytes_por_linha_mascara = ((tamanho + 31) // 32) * 4
    mascara = b"\x00" * (bytes_por_linha_mascara * tamanho)
    return cabecalho + render_eye(tamanho) + mascara


def ico_bytes(tamanhos: tuple[int, ...] = TAMANHOS) -> bytes:
    """Arquivo ICO completo com uma imagem por tamanho pedido."""
    imagens = [_dib(tamanho) for tamanho in tamanhos]
    deslocamento = 6 + 16 * len(imagens)
    entradas = bytearray()
    for tamanho, imagem in zip(tamanhos, imagens, strict=True):
        entradas += struct.pack(
            "<BBBBHHII", tamanho % 256, tamanho % 256, 0, 0, 1, 32, len(imagem), deslocamento
        )
        deslocamento += len(imagem)
    return struct.pack("<HHH", 0, 1, len(imagens)) + bytes(entradas) + b"".join(imagens)


def write_ico(destino: Path, tamanhos: tuple[int, ...] = TAMANHOS) -> Path:
    """Grava o icone, criando o diretorio se preciso."""
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_bytes(ico_bytes(tamanhos))
    return destino


def main(argv: list[str] | None = None) -> int:
    """Gera o icone no caminho informado."""
    argumentos = sys.argv[1:] if argv is None else argv
    if len(argumentos) != 1:
        print("uso: python -m kiro_eye_monitor.eye_icon <caminho.ico>", file=sys.stderr)
        return 2
    print(write_ico(Path(argumentos[0])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
