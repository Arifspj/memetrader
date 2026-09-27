"""Internal domain types shared by scanner, scoring, risk and execution layers.

These are plain dataclasses (not ORM rows) so the engine can be unit tested
without a database.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from enum import StrEnum


def utcnow() -> datetime:
    return datetime.now(UTC)


class Side(StrEnum):
    BUY = "buy"
    SELL = "sell"


class ExitReason(StrEnum):
    TAKE_PROFIT = "tp"
    STOP_LOSS = "sl"
    TRAILING_STOP = "trailing"
    AI_SIGNAL = "ai_signal"
    SCORE_COLLAPSE = "score_collapse"
    LIQUIDITY_COLLAPSE = "liquidity_collapse"
    WHALE_DUMP = "whale_dump"
    MAX_HOLD = "max_hold"
    DAILY_LOSS_LIMIT = "daily_loss_limit"
    RISK_HALT = "risk_halt"
    MANUAL_CLOSE = "manual_close"
    CLOSE_ALL = "close_all"
    STOP_BOT = "stop_bot"


class RunState(StrEnum):
    STOPPED = "stopped"
    RUNNING = "running"


@dataclass(slots=True)
class TokenSnapshot:
    """Market data for one Solana pair at a point in time."""

    chain: str
    pair_address: str
    dex_id: str
    symbol: str
    name: str | None = None
    mint: str | None = None
    image_url: str | None = None

    price_usd: float = 0.0
    liquidity_usd: float = 0.0
    volume_5m: float = 0.0
    volume_24h: float = 0.0
    price_change_5m: float = 0.0
    price_change_1h: float = 0.0
    price_change_24h: float = 0.0
    txns_5m_buys: int = 0
    txns_5m_sells: int = 0
    pair_created_at: datetime | None = None
    fetched_at: datetime = field(default_factory=utcnow)

    @property
    def buy_sell_ratio(self) -> float:
        if self.txns_5m_sells <= 0:
            return float(self.txns_5m_buys) if self.txns_5m_buys else 0.0
        return self.txns_5m_buys / self.txns_5m_sells

    @property
    def volume_liquidity_ratio(self) -> float:
        if self.liquidity_usd <= 0:
            return 0.0
        return self.volume_5m / self.liquidity_usd

    @property
    def age_minutes(self) -> float | None:
        if not self.pair_created_at:
            return None
        created = self.pair_created_at
        if created.tzinfo is None:
            created = created.replace(tzinfo=UTC)
        return max(0.0, (utcnow() - created).total_seconds() / 60)


@dataclass(slots=True)
class SafetyReport:
    passed: bool
    score: float
    flags: list[str] = field(default_factory=list)
    blocking: list[str] = field(default_factory=list)

    def add(self, flag: str, penalty: float) -> None:
        """Soft flag: reduces the score but does not block on its own."""
        self.score = max(0.0, self.score - penalty)
        self.flags.append(flag)

    def block(self, flag: str, penalty: float = 0.0) -> None:
        """Hard flag: the token is never tradable, whatever the score."""
        self.add(flag, penalty)
        self.blocking.append(flag)


@dataclass(slots=True)
class ScoreBreakdown:
    total: float = 0.0
    liquidity: float = 0.0
    volume_accel: float = 0.0
    momentum: float = 0.0
    buy_pressure: float = 0.0
    whale: float = 0.0
    holder: float = 0.0
    market: float = 0.0
    safety: float = 0.0

    def as_dict(self) -> dict[str, float]:
        return {
            "total": round(self.total, 2),
            "liquidity": round(self.liquidity, 2),
            "volume_accel": round(self.volume_accel, 2),
            "momentum": round(self.momentum, 2),
            "buy_pressure": round(self.buy_pressure, 2),
            "whale": round(self.whale, 2),
            "holder": round(self.holder, 2),
            "market": round(self.market, 2),
            "safety": round(self.safety, 2),
        }


@dataclass(slots=True)
class Candidate:
    snapshot: TokenSnapshot
    safety: SafetyReport
    score: ScoreBreakdown
    blocked_reasons: list[str] = field(default_factory=list)

    @property
    def symbol(self) -> str:
        return self.snapshot.symbol

    @property
    def total_score(self) -> float:
        return self.score.total

    @property
    def is_tradable(self) -> bool:
        return not self.blocked_reasons


@dataclass(slots=True)
class RiskDecision:
    approved: bool
    usd_size: float
    reasons: list[str] = field(default_factory=list)
    halt: bool = False


@dataclass(slots=True)
class ExitSignal:
    reason: ExitReason
    price: float
    detail: str = ""


@dataclass(slots=True)
class FillResult:
    side: Side
    symbol: str
    mint: str
    pair_address: str
    dex_id: str
    usd_amount: float
    qty: float
    price: float
    tx_signature: str | None = None
    price_impact_bps: float | None = None
    route_summary: str | None = None
    fees_usd: float = 0.0
    pending_signature: str | None = None
