"""Modelos de dominio do coletor de consumo Kiro.

Todo valor esta em creditos fracionados, que e a unidade de cobranca do Kiro
(medida em incrementos de 0.01). Tokens nao servem: o servico devolve
input_token_count/output_token_count zerados nos arquivos de sessao.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime


@dataclass(frozen=True, slots=True)
class AccountUsage:
    """Total autoritativo da conta, extraido do comando /usage do kiro-cli.

    Cobre todos os clientes (IDE, CLI, web, mobile) porque o pool de credito e
    unico por conta.

    >>> usage.credits_used, usage.credits_included
    (2271.91, 10000.0)
    """

    plan_name: str
    credits_used: float
    credits_included: float
    used_percent: int
    resets_on: date
    captured_at: datetime

    @property
    def credits_remaining(self) -> float:
        """Saldo restante do ciclo, nunca negativo (overage vira zero)."""
        return max(0.0, self.credits_included - self.credits_used)


@dataclass(frozen=True, slots=True)
class TurnRecord:
    """Um turno de conversa do kiro-cli com o credito que ele consumiu.

    Vem de session_state.conversation_metadata.user_turn_metadatas[] nos
    arquivos ~/.kiro/sessions/cli/<uuid>.json.
    """

    session_id: str
    session_title: str
    project_path: str
    model: str | None
    credits: float
    ended_at: datetime
    duration_seconds: float
    end_reason: str | None


@dataclass(frozen=True, slots=True)
class CreditGroup:
    """Creditos somados sob um rotulo (um projeto ou um modelo)."""

    label: str
    credits: float
    turn_count: int


@dataclass(frozen=True, slots=True)
class DailyCredits:
    """Consumo de um dia do calendario local.

    ``chat_count`` acompanha o total porque um dia caro com uma conversa so tem
    causa diferente de um dia caro espalhado por dez.
    """

    day: date
    credits: float
    turn_count: int
    chat_count: int


@dataclass(frozen=True, slots=True)
class ChatCredits:
    """Consumo de uma conversa do kiro-cli (um arquivo de sessao).

    O ``title`` e o primeiro prompt da conversa, que e o que o kiro-cli grava no
    campo ``title`` do arquivo de sessao; e o unico rotulo legivel disponivel,
    ja que o ``session_id`` e um UUID.
    """

    session_id: str
    title: str
    project_path: str
    credits: float
    turn_count: int
    first_turn_at: datetime
    last_turn_at: datetime


@dataclass(frozen=True, slots=True)
class CliBreakdown:
    """Detalhamento do consumo rastreavel do kiro-cli nesta maquina."""

    period_start: date
    total_credits: float
    turn_count: int
    by_project: tuple[CreditGroup, ...]
    by_model: tuple[CreditGroup, ...]
    by_day: tuple[DailyCredits, ...]
    by_chat: tuple[ChatCredits, ...]


@dataclass(frozen=True, slots=True)
class CyclePace:
    """Ritmo medio de consumo no ciclo de faturamento.

    Medido sobre o mes inteiro, nao sobre a distancia entre duas leituras: o
    Kiro so expoe um acumulado, e a media do ciclo e a leitura estavel dele.
    """

    period_start: date
    period_end: date
    elapsed_days: float
    total_days: float
    credits_per_day: float
    projected_cycle_usage: float
    projected_exhaustion: date | None

    @property
    def remaining_days(self) -> float:
        """Dias que faltam para o reset."""
        return max(0.0, self.total_days - self.elapsed_days)

    @property
    def exhausts_before_reset(self) -> bool:
        """Se a cota acaba antes do fim do ciclo, mantido o ritmo."""
        if self.projected_exhaustion is None:
            return False
        return self.projected_exhaustion < self.period_end


@dataclass(frozen=True, slots=True)
class UsageSnapshot:
    """Leitura pontual do total da conta, persistida para calcular tendencia."""

    captured_at: datetime
    plan_name: str
    credits_used: float
    credits_included: float
    resets_on: date


@dataclass(frozen=True, slots=True)
class UsageReport:
    """Payload consolidado que o coletor entrega para a janela do Windows."""

    account: AccountUsage
    cycle_pace: CyclePace | None
    cli_breakdown: CliBreakdown | None
    unattributed_credits: float | None
