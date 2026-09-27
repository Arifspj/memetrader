"""Pydantic request/response models for the API layer."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---------------- auth / wallet ----------------


class LoginRequest(BaseModel):
    """Phantom Connect hands the app a signed nonce; the backend verifies it."""

    wallet_address: str
    message: str
    signature: str


class WalletOut(BaseModel):
    wallet_address: str
    balance_sol: float | None = None
    balance_usdc: float | None = None
    has_session_key: bool = False
    execution_mode: str


# ---------------- settings ----------------


class SettingsOut(ORMModel):
    starting_capital_usd: float
    risk_per_trade_pct: float
    max_open_positions: int
    max_daily_loss_pct: float
    take_profit_pct: float
    stop_loss_pct: float
    trailing_activation_pct: float
    trailing_drop_pct: float
    max_hold_minutes: int
    min_entry_score: float
    reentry_cooldown_minutes: int
    min_liquidity_usd: float
    min_volume_5m_usd: float
    max_price_impact_bps: float
    scan_interval_seconds: int
    alerts_enabled: bool


class SettingsUpdate(BaseModel):
    starting_capital_usd: float | None = Field(default=None, gt=0)
    risk_per_trade_pct: float | None = Field(default=None, gt=0, le=100)
    max_open_positions: int | None = Field(default=None, ge=1, le=20)
    max_daily_loss_pct: float | None = Field(default=None, gt=0, le=100)
    take_profit_pct: float | None = Field(default=None, gt=0)
    stop_loss_pct: float | None = Field(default=None, gt=0)
    trailing_activation_pct: float | None = Field(default=None, ge=0)
    trailing_drop_pct: float | None = Field(default=None, gt=0)
    max_hold_minutes: int | None = Field(default=None, ge=1)
    min_entry_score: float | None = Field(default=None, ge=0, le=100)
    reentry_cooldown_minutes: int | None = Field(default=None, ge=0)
    min_liquidity_usd: float | None = Field(default=None, ge=0)
    min_volume_5m_usd: float | None = Field(default=None, ge=0)
    max_price_impact_bps: float | None = Field(default=None, gt=0)
    scan_interval_seconds: int | None = Field(default=None, ge=5)
    alerts_enabled: bool | None = None


# ---------------- bot control ----------------


class BotStateOut(BaseModel):
    state: str
    mode: str
    run_id: str | None = None
    started_at: datetime | None = None
    last_heartbeat: datetime | None = None
    scanning: bool = False
    tokens_scanned: int = 0
    opportunities: int = 0
    open_positions: int = 0
    equity_usd: float = 0.0
    today_pnl_usd: float = 0.0
    today_trades: int = 0
    win_rate: float | None = None


# ---------------- market / trade ----------------


class TokenOut(BaseModel):
    symbol: str
    name: str | None = None
    mint: str | None = None
    pair_address: str
    dex_id: str
    price_usd: float
    liquidity_usd: float
    volume_5m: float
    price_change_5m: float
    buy_sell_ratio: float
    score: float | None = None
    blocked_reasons: list[str] = Field(default_factory=list)
    score_breakdown: dict[str, float] | None = None


class OpportunityListOut(BaseModel):
    scanned: int
    count: int
    items: list[TokenOut]


class PositionOut(ORMModel):
    id: str
    symbol: str
    name: str | None
    mint: str
    status: str
    qty: float
    entry_price: float
    current_price: float | None
    invested_usd: float
    entry_score: float
    stop_loss: float | None
    take_profit: float | None
    trailing_stop: float | None
    unrealized_pnl_usd: float
    unrealized_pnl_pct: float
    opened_at: datetime
    closed_at: datetime | None = None
    exit_price: float | None = None
    exit_reason: str | None = None
    realized_pnl_usd: float | None = None


class TradeOut(ORMModel):
    id: str
    side: str
    mode: str
    symbol: str
    usd_amount: float
    qty: float
    price: float
    reason: str | None
    pnl_usd: float | None
    tx_signature: str | None
    status: str
    created_at: datetime


class EventOut(ORMModel):
    id: str
    level: str
    category: str
    symbol: str | None
    message: str
    payload: dict | None
    created_at: datetime


class PortfolioOut(BaseModel):
    equity_usd: float
    cash_usd: float
    invested_usd: float
    realized_pnl_usd: float
    unrealized_pnl_usd: float
    today_pnl_usd: float
    today_pnl_pct: float
    open_positions: int
    total_trades: int
    wins: int
    losses: int
    win_rate: float | None
    starting_capital_usd: float


class CloseAllRequest(BaseModel):
    reason: str = "close_all"
