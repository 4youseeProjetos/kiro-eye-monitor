"""Testes do gerador do icone do olho."""

from __future__ import annotations

import struct
from pathlib import Path

from kiro_eye_monitor.eye_icon import COR_FUNDO, COR_OLHO, ico_bytes, render_eye, write_ico


def _pixel(dados: bytes, tamanho: int, coluna: int, linha_de_cima: int) -> tuple[int, int, int]:
    """Cor RGB de um pixel, convertendo do BGRA de baixo para cima do DIB."""
    linha = tamanho - 1 - linha_de_cima
    inicio = (linha * tamanho + coluna) * 4
    azul, verde, vermelho, _alfa = dados[inicio : inicio + 4]
    return (vermelho, verde, azul)


def test_tamanho_do_buffer_de_pixels() -> None:
    assert len(render_eye(16)) == 16 * 16 * 4


def test_todos_os_pixels_sao_opacos() -> None:
    dados = render_eye(16)

    assert all(dados[i] == 255 for i in range(3, len(dados), 4))


def test_centro_da_iris_usa_a_cor_do_olho() -> None:
    tamanho = 32
    centro = _pixel(render_eye(tamanho), tamanho, tamanho // 2, tamanho // 2)

    assert centro == COR_OLHO


def test_a_cor_do_olho_e_azul() -> None:
    vermelho, verde, azul = COR_OLHO

    assert azul > verde > vermelho, f"esperado azul dominante, recebido {COR_OLHO}"


def test_canto_superior_esquerdo_usa_a_cor_de_fundo() -> None:
    assert _pixel(render_eye(32), 32, 0, 0) == COR_FUNDO


def test_meio_da_borda_superior_e_fundo_pois_o_olho_e_amendoado() -> None:
    tamanho = 32

    assert _pixel(render_eye(tamanho), tamanho, tamanho // 2, 0) == COR_FUNDO


def test_contorno_da_palpebra_tem_pixel_colorido_na_lateral() -> None:
    tamanho = 48
    dados = render_eye(tamanho)
    meio = tamanho // 2
    laterais = [_pixel(dados, tamanho, coluna, meio) for coluna in (1, 2, 3)]

    assert any(cor[2] > 100 for cor in laterais)


def test_cabecalho_do_ico_declara_todas_as_imagens() -> None:
    dados = ico_bytes((16, 32))
    reservado, tipo, quantidade = struct.unpack("<HHH", dados[:6])

    assert (reservado, tipo, quantidade) == (0, 1, 2)


def test_entradas_do_ico_apontam_para_dentro_do_arquivo() -> None:
    dados = ico_bytes((16, 32, 48))

    for indice in range(3):
        entrada = dados[6 + 16 * indice : 6 + 16 * (indice + 1)]
        largura, _altura, _cores, _res, _planos, bits, tamanho, offset = struct.unpack(
            "<BBBBHHII", entrada
        )
        assert bits == 32
        assert largura in (16, 32, 48)
        assert offset + tamanho <= len(dados)


def test_grava_o_arquivo_criando_o_diretorio(tmp_path: Path) -> None:
    destino = write_ico(tmp_path / "assets" / "eye.ico", (16,))

    assert destino.exists()
    assert destino.read_bytes()[:4] == b"\x00\x00\x01\x00"
