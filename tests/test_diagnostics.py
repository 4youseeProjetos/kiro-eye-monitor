"""Testes do retrato de ambiente anexado ao log de falhas."""

from __future__ import annotations

from pathlib import Path

from kiro_eye_monitor.diagnostics import describe_environment


def test_aponta_o_caminho_absoluto_do_kiro_cli(tmp_path: Path, monkeypatch) -> None:
    binario = tmp_path / "kiro-cli"
    binario.write_text("#!/bin/sh\n", encoding="utf-8")
    binario.chmod(0o755)
    monkeypatch.setenv("PATH", str(tmp_path))

    ambiente = describe_environment("kiro-cli", tmp_path)

    assert ambiente["kiro_cli"] == str(binario)


def test_avisa_quando_o_kiro_cli_esta_fora_do_path(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("PATH", str(tmp_path))

    ambiente = describe_environment("kiro-cli", tmp_path)

    assert ambiente["kiro_cli"] == "kiro-cli (fora do PATH)"


def test_avisa_quando_o_caminho_informado_nao_existe(tmp_path: Path) -> None:
    ambiente = describe_environment("/opt/kiro/bin/kiro-cli", tmp_path)

    assert ambiente["kiro_cli"] == "/opt/kiro/bin/kiro-cli (inexistente)"


def test_aceita_caminho_informado_existente(tmp_path: Path) -> None:
    binario = tmp_path / "kiro-cli"
    binario.write_text("#!/bin/sh\n", encoding="utf-8")

    ambiente = describe_environment(str(binario), tmp_path)

    assert ambiente["kiro_cli"] == str(binario)


def test_conta_os_arquivos_de_sessao(tmp_path: Path) -> None:
    sessoes = tmp_path / "cli"
    sessoes.mkdir()
    for indice in range(3):
        (sessoes / f"{indice}.json").write_text("{}", encoding="utf-8")

    ambiente = describe_environment("kiro-cli", sessoes)

    assert ambiente["sessoes"] == f"{sessoes} (3 arquivos json)"


def test_avisa_diretorio_de_sessoes_inexistente(tmp_path: Path) -> None:
    ausente = tmp_path / "nao-existe"

    ambiente = describe_environment("kiro-cli", ausente)

    assert ambiente["sessoes"] == f"{ausente} (inexistente)"


def test_registra_a_distro_do_wsl(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("WSL_DISTRO_NAME", "Ubuntu-24.04")

    assert describe_environment("kiro-cli", tmp_path)["distro"] == "Ubuntu-24.04"


def test_marca_execucao_fora_do_wsl(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("WSL_DISTRO_NAME", raising=False)

    assert describe_environment("kiro-cli", tmp_path)["distro"] == "(fora do WSL)"


def test_inclui_python_e_path(tmp_path: Path) -> None:
    ambiente = describe_environment("kiro-cli", tmp_path)

    assert ambiente["python"].count(".") >= 1
    assert "path" in ambiente
