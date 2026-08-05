"""Leitura da fonte B: os arquivos de sessao que o kiro-cli grava em disco.

Cada ``~/.kiro/sessions/cli/<uuid>.json`` guarda, por turno de conversa, o
credito consumido em ``metering_usage[].value``. Leitura local, custo zero de
credito.

O acesso passa por :class:`SessionReader` para que o agregador nao saiba de
onde vieram os turnos: hoje so o kiro-cli sabe informar credito por turno, e
quando o IDE passar a persistir esse dado basta trocar a implementacao.
"""

from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Protocol

from kiro_eye_monitor.models import TurnRecord

_CREDIT_UNIT = "credit"


class SessionReader(Protocol):
    """Fonte de turnos com credito atribuido a um projeto."""

    def read_turns(self) -> tuple[TurnRecord, ...]:
        """Devolve todos os turnos com credito conhecido, sem filtro de periodo."""


def default_cli_sessions_dir() -> Path:
    """Diretorio de sessoes do kiro-cli, respeitando ``KIRO_HOME``."""
    kiro_home = os.environ.get("KIRO_HOME")
    base = Path(kiro_home) if kiro_home else Path.home() / ".kiro"
    return base / "sessions" / "cli"


class CliSessionReader:
    """Le os turnos das sessoes do kiro-cli em ``sessions_dir``.

    >>> CliSessionReader(default_cli_sessions_dir()).read_turns()[0].project_path
    '/home/dev/loja-online'
    """

    def __init__(self, sessions_dir: Path) -> None:
        self._sessions_dir = sessions_dir

    def read_turns(self) -> tuple[TurnRecord, ...]:
        if not self._sessions_dir.is_dir():
            return ()
        turns: list[TurnRecord] = []
        for path in sorted(self._sessions_dir.glob("*.json")):
            turns.extend(self._turns_of_file(path))
        return tuple(turns)

    def _turns_of_file(self, path: Path) -> list[TurnRecord]:
        """Turnos de um arquivo; arquivo ilegivel e ignorado em vez de derrubar a coleta."""
        session = _load_json_object(path)
        if not session:
            return []
        session_id = _as_str(session.get("session_id")) or path.stem
        title = _as_str(session.get("title")).strip()
        project_path = _as_str(session.get("cwd")) or "(desconhecido)"
        built = (
            _build_turn(session_id, title, project_path, _as_dict(raw))
            for raw in _turn_metadatas(session)
        )
        return [turn for turn in built if turn is not None]


class IdeSessionReader:
    """Placeholder para o Kiro IDE, que hoje nao persiste credito por turno.

    O IDE mostra "Est. Credits Used" na interface mas nao grava o valor em
    ``globalStorage/kiro.kiroagent/`` — ver kirodotdev/Kiro#8524. Enquanto isso
    o consumo do IDE aparece so no total da conta (fonte A), como resto nao
    atribuido.
    """

    def read_turns(self) -> tuple[TurnRecord, ...]:
        return ()


def _turn_metadatas(session: dict[str, object]) -> list[object]:
    """Caminho ``session_state.conversation_metadata.user_turn_metadatas``."""
    state = _as_dict(session.get("session_state"))
    metadata = _as_dict(state.get("conversation_metadata"))
    return _as_list(metadata.get("user_turn_metadatas"))


def _build_turn(
    session_id: str,
    session_title: str,
    project_path: str,
    raw: dict[str, object],
) -> TurnRecord | None:
    """Monta um turno; devolve ``None`` se nao houver credito ou horario."""
    credits = _sum_credits(_as_list(raw.get("metering_usage")))
    ended_at = _parse_timestamp(_as_str(raw.get("end_timestamp")))
    if credits <= 0.0 or ended_at is None:
        return None
    return TurnRecord(
        session_id=session_id,
        session_title=session_title,
        project_path=project_path,
        model=_as_str(raw.get("model")) or None,
        credits=credits,
        ended_at=ended_at,
        duration_seconds=_duration_seconds(_as_dict(raw.get("turn_duration"))),
        end_reason=_as_str(raw.get("end_reason")) or None,
    )


def _sum_credits(metering_usage: list[object]) -> float:
    """Soma as entradas cuja unidade e credito, ignorando outras unidades."""
    total = 0.0
    for entry in metering_usage:
        item = _as_dict(entry)
        if _as_str(item.get("unit")) != _CREDIT_UNIT:
            continue
        total += _as_float(item.get("value"))
    return total


def _duration_seconds(turn_duration: dict[str, object]) -> float:
    """Converte ``{"secs": 1, "nanos": 706771573}`` em segundos."""
    return _as_float(turn_duration.get("secs")) + _as_float(turn_duration.get("nanos")) / 1e9


def _parse_timestamp(raw: str) -> datetime | None:
    """Le o ISO-8601 com sufixo Z; devolve ``None`` se ausente ou invalido."""
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _load_json_object(path: Path) -> dict[str, object]:
    """Carrega um objeto JSON; devolve vazio se o arquivo estiver corrompido."""
    try:
        content = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return {}
    return _as_dict(content)


def _as_dict(value: object) -> dict[str, object]:
    return value if isinstance(value, dict) else {}


def _as_list(value: object) -> list[object]:
    return value if isinstance(value, list) else []


def _as_str(value: object) -> str:
    return value if isinstance(value, str) else ""


def _as_float(value: object) -> float:
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else 0.0
