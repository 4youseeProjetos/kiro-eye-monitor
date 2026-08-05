"""Entrypoint do coletor: imprime o relatorio de consumo em JSON no stdout.

Chamado pela janela do Windows via
``wsl.exe -d Ubuntu -- <projeto>/scripts/collect.sh [--account-only]``.

Erros saem como JSON com a chave ``error`` e codigo de saida 1, para que a
janela possa exibir a falha em vez de travar esperando um payload valido.
"""

from __future__ import annotations

import argparse
import json
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path

from kiro_eye_monitor.collector import UsageCollector
from kiro_eye_monitor.diagnostics import describe_environment
from kiro_eye_monitor.error_log import JsonlErrorLog, default_log_path
from kiro_eye_monitor.serialization import report_to_dict
from kiro_eye_monitor.session_reader import CliSessionReader, default_cli_sessions_dir
from kiro_eye_monitor.snapshot_store import SnapshotStore
from kiro_eye_monitor.usage_command import (
    DEFAULT_TIMEOUT_SECONDS,
    KiroCliUsageCommand,
    UsageCommandError,
)

_EXIT_ERROR = 1


def default_db_path() -> Path:
    """Banco de snapshots em XDG data, fora do diretorio do projeto."""
    return Path.home() / ".local" / "share" / "kiro-eye-monitor" / "snapshots.db"


def build_parser() -> argparse.ArgumentParser:
    """Argumentos do coletor."""
    parser = argparse.ArgumentParser(description="Coleta o consumo de creditos Kiro em JSON.")
    parser.add_argument(
        "--account-only",
        action="store_true",
        help="apenas o total da conta; nao varre os arquivos de sessao do kiro-cli",
    )
    parser.add_argument("--sessions-dir", type=Path, default=default_cli_sessions_dir())
    parser.add_argument("--db", type=Path, default=default_db_path())
    parser.add_argument("--kiro-cli", default="kiro-cli")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument("--log", type=Path, default=default_log_path())
    return parser


def _build_collector(options: argparse.Namespace) -> UsageCollector:
    """Monta o coletor com as dependencias reais."""
    return UsageCollector(
        account_source=KiroCliUsageCommand(options.kiro_cli, options.timeout),
        session_reader=CliSessionReader(options.sessions_dir),
        snapshot_store=SnapshotStore(options.db),
        clock=lambda: datetime.now(timezone.utc),
        # astimezone() sem argumento resolve o fuso do sistema no instante do
        # turno, o que mantem o dia certo mesmo com horario de verao no meio do
        # ciclo.
        local_time=lambda momento: momento.astimezone(),
    )


def _registrar_falha(options: argparse.Namespace, erro: Exception) -> Path:
    """Grava a falha com o contexto do ambiente e devolve o caminho do log."""
    log = JsonlErrorLog(options.log, lambda: datetime.now(timezone.utc))
    return log.record(
        message=str(erro),
        context=describe_environment(options.kiro_cli, options.sessions_dir),
        traceback_text="".join(traceback.format_exception(erro)),
    )


def main(argv: list[str] | None = None) -> int:
    """Imprime o relatorio em JSON; devolve o codigo de saida do processo."""
    options = build_parser().parse_args(argv)
    try:
        report = _build_collector(options).collect(include_cli_detail=not options.account_only)
    except (UsageCommandError, ValueError, OSError) as erro:
        caminho = _registrar_falha(options, erro)
        falha = {"error": str(erro), "log_path": str(caminho)}
        print(json.dumps(falha, ensure_ascii=False), file=sys.stdout)
        return _EXIT_ERROR
    print(json.dumps(report_to_dict(report), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
