"""Database models: users, bot settings, discovered tokens, positions, trades, events."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import (
    JSON,
    Boolean,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base, UTCDateTime


def _uuid() -> str:
    return uuid.uuid4().hex


def utcnow() -> datetime:
    return datetime.now(UTC)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        UTCDateTime, default=utcnow, onupdate=utcnow, nullable=False
    )


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    # Phantom embedded wallet public key
    wallet_address: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(64))

    settings: Mapped[BotSettings | None] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan"
    )
    positions: Mapped[list[Position]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    trades: Mapped[list[Trade]] = relationship(back_populates="user", cascade="all, delete-orphan")


class BotSettings(Base, TimestampMixin):
    __tablename__ = "bot_settings"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )

    starting_capital_usd: Mapped[float] = mapped_column(Float, default=1000.0)
    risk_per_trade_pct: Mapped[float] = mapped_column(Float, default=1.0)
    max_open_positions: Mapped[int] = mapped_column(Integer, default=5)
    max_daily_loss_pct: Mapped[float] = mapped_column(Float, default=5.0)

    take_profit_pct: Mapped[float] = mapped_column(Float, default=12.0)
    stop_loss_pct: Mapped[float] = mapped_column(Float, default=6.0)
    trailing_activation_pct: Mapped[float] = mapped_column(Float, default=8.0)
    trailing_drop_pct: Mapped[float] = mapped_column(Float, default=4.0)
    max_hold_minutes: Mapped[int] = mapped_column(Integer, default=240)
    min_entry_score: Mapped[float] = mapped_column(Float, default=80.0)
    # after an exit the bot must not immediately re-buy the same token
    reentry_cooldown_minutes: Mapped[int] = mapped_column(Integer, default=15)

    min_liquidity_usd: Mapped[float] = mapped_column(Float, default=50_000.0)
    min_volume_5m_usd: Mapped[float] = mapped_column(Float, default=20_000.0)
    max_price_impact_bps: Mapped[float] = mapped_column(Float, default=150.0)
    scan_interval_seconds: Mapped[int] = mapped_column(Integer, default=20)
    alerts_enabled: Mapped[bool] = mapped_column(Boolean, default=True)

    user: Mapped[User] = relationship(back_populates="settings")


class BotRun(Base, TimestampMixin):
    """One START -> STOP session."""

    __tablename__ = "bot_runs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(16), default="stopped")  # running|stopped
    mode: Mapped[str] = mapped_column(String(16), default="paper")
    started_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    stopped_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    last_heartbeat: Mapped[datetime | None] = mapped_column(UTCDateTime)
    error: Mapped[str | None] = mapped_column(Text)


class Token(Base, TimestampMixin):
    """Discovered Solana pair, kept hot in Redis/in-memory between scans."""

    __tablename__ = "tokens"
    __table_args__ = (UniqueConstraint("chain", "pair_address", name="uq_token_pair"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    chain: Mapped[str] = mapped_column(String(16), default="solana", index=True)
    pair_address: Mapped[str] = mapped_column(String(64), index=True)
    mint: Mapped[str | None] = mapped_column(String(64), index=True)
    dex_id: Mapped[str] = mapped_column(String(32))
    symbol: Mapped[str] = mapped_column(String(32), index=True)
    name: Mapped[str | None] = mapped_column(String(128))
    image_url: Mapped[str | None] = mapped_column(Text)

    price_usd: Mapped[float | None] = mapped_column(Float)
    liquidity_usd: Mapped[float | None] = mapped_column(Float)
    volume_5m: Mapped[float | None] = mapped_column(Float)
    volume_24h: Mapped[float | None] = mapped_column(Float)
    price_change_5m: Mapped[float | None] = mapped_column(Float)
    price_change_1h: Mapped[float | None] = mapped_column(Float)
    price_change_24h: Mapped[float | None] = mapped_column(Float)
    txns_5m_buys: Mapped[int | None] = mapped_column(Integer)
    txns_5m_sells: Mapped[int | None] = mapped_column(Integer)
    pair_created_at: Mapped[datetime | None] = mapped_column(UTCDateTime)

    last_score: Mapped[float | None] = mapped_column(Float)
    last_score_breakdown: Mapped[dict | None] = mapped_column(JSON)
    last_seen_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)


class Position(Base, TimestampMixin):
    __tablename__ = "positions"
    __table_args__ = (Index("ix_position_user_status", "user_id", "status"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    run_id: Mapped[str | None] = mapped_column(String(32), index=True)

    mint: Mapped[str] = mapped_column(String(64), index=True)
    pair_address: Mapped[str] = mapped_column(String(64))
    dex_id: Mapped[str] = mapped_column(String(32))
    symbol: Mapped[str] = mapped_column(String(32), index=True)
    name: Mapped[str | None] = mapped_column(String(128))

    status: Mapped[str] = mapped_column(String(16), default="open", index=True)
    qty: Mapped[float] = mapped_column(Float, default=0.0)
    entry_price: Mapped[float] = mapped_column(Float)
    invested_usd: Mapped[float] = mapped_column(Float)
    fees_usd: Mapped[float] = mapped_column(Float, default=0.0)
    entry_score: Mapped[float] = mapped_column(Float, default=0.0)
    entry_reason: Mapped[str | None] = mapped_column(Text)

    current_price: Mapped[float | None] = mapped_column(Float)
    peak_price: Mapped[float] = mapped_column(Float, default=0.0)
    entry_liquidity_usd: Mapped[float] = mapped_column(Float, default=0.0)
    stop_loss: Mapped[float | None] = mapped_column(Float)
    take_profit: Mapped[float | None] = mapped_column(Float)
    trailing_stop: Mapped[float | None] = mapped_column(Float)
    score_at_entry: Mapped[float] = mapped_column(Float, default=0.0)

    opened_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    closed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    exit_price: Mapped[float | None] = mapped_column(Float)
    exit_reason: Mapped[str | None] = mapped_column(String(32))
    realized_pnl_usd: Mapped[float | None] = mapped_column(Float)

    user: Mapped[User] = relationship(back_populates="positions")


class Trade(Base):
    """An executed swap (paper or real)."""

    __tablename__ = "trades"
    __table_args__ = (Index("ix_trade_user_created", "user_id", "created_at"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    position_id: Mapped[str | None] = mapped_column(String(32), index=True)
    run_id: Mapped[str | None] = mapped_column(String(32), index=True)

    side: Mapped[str] = mapped_column(String(8))  # buy | sell
    mode: Mapped[str] = mapped_column(String(16), default="paper")
    status: Mapped[str] = mapped_column(String(16), default="filled")  # filled|pending|failed

    mint: Mapped[str] = mapped_column(String(64), index=True)
    pair_address: Mapped[str] = mapped_column(String(64))
    dex_id: Mapped[str] = mapped_column(String(32), default="")
    symbol: Mapped[str] = mapped_column(String(32), index=True)

    usd_amount: Mapped[float] = mapped_column(Float)
    qty: Mapped[float] = mapped_column(Float)
    price: Mapped[float] = mapped_column(Float)
    price_impact_bps: Mapped[float | None] = mapped_column(Float)
    slippage_bps: Mapped[float | None] = mapped_column(Float)
    tx_signature: Mapped[str | None] = mapped_column(String(128), index=True)
    route_summary: Mapped[str | None] = mapped_column(Text)
    reason: Mapped[str | None] = mapped_column(String(32))
    pnl_usd: Mapped[float | None] = mapped_column(Float)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, nullable=False)

    user: Mapped[User] = relationship(back_populates="trades")


class BotEvent(Base):
    """Human readable log line -> the Logs tab."""

    __tablename__ = "bot_events"
    __table_args__ = (Index("ix_event_user_created", "user_id", "created_at"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    level: Mapped[str] = mapped_column(String(8), default="info")
    category: Mapped[str] = mapped_column(String(24), default="system")
    symbol: Mapped[str | None] = mapped_column(String(32))
    message: Mapped[str] = mapped_column(Text)
    payload: Mapped[dict | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow, nullable=False)


class EquitySnapshot(Base):
    __tablename__ = "equity_snapshots"
    __table_args__ = (Index("ix_equity_user_ts", "user_id", "ts"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    ts: Mapped[datetime] = mapped_column(UTCDateTime, default=utcnow)
    equity_usd: Mapped[float] = mapped_column(Float)
    cash_usd: Mapped[float] = mapped_column(Float)
    invested_usd: Mapped[float] = mapped_column(Float)
    realized_pnl_usd: Mapped[float] = mapped_column(Float)
    unrealized_pnl_usd: Mapped[float] = mapped_column(Float)
    open_positions: Mapped[int] = mapped_column(Integer, default=0)
