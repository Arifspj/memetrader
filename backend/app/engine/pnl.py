"""Portfolio maths: equity, cash, realised/unrealised P&L, win rate.

Pure functions over any object exposing the Position attributes, so these can be
unit tested with simple stand-ins.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime, time


@dataclass(slots=True)
class Portfolio:
    starting_capital_usd: float
    cash_usd: float
    invested_usd: float
    market_value_usd: float
    equity_usd: float
    realized_pnl_usd: float
    unrealized_pnl_usd: float
    realized_today_usd: float
    today_pnl_usd: float
    open_positions: int
    total_trades: int
    wins: int
    losses: int

    @property
    def win_rate(self) -> float | None:
        closed = self.wins + self.losses
        return round(self.wins / closed * 100, 2) if closed else None

    @property
    def today_pnl_pct(self) -> float:
        base = self.equity_usd - self.today_pnl_usd
        return round(self.today_pnl_usd / base * 100, 2) if base > 0 else 0.0


def position_market_value(position) -> float:
    price = position.current_price or position.entry_price
    return (position.qty or 0.0) * price


def unrealized_pnl(position) -> float:
    return position_market_value(position) - (position.invested_usd or 0.0)


def unrealized_pnl_pct(position) -> float:
    if not position.invested_usd:
        return 0.0
    return round(unrealized_pnl(position) / position.invested_usd * 100, 2)


def start_of_utc_day(moment: datetime | None = None) -> datetime:
    moment = moment or datetime.now(UTC)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=UTC)
    return datetime.combine(moment.date(), time.min, tzinfo=UTC)


def compute_portfolio(
    *,
    starting_capital_usd: float,
    open_positions: Iterable,
    closed_positions: Iterable = (),
    realized_today_usd: float = 0.0,
    fees_paid_usd: float = 0.0,
) -> Portfolio:
    open_positions = list(open_positions)
    closed_positions = list(closed_positions)

    invested = sum(p.invested_usd or 0.0 for p in open_positions)
    market_value = sum(position_market_value(p) for p in open_positions)
    unrealized = market_value - invested
    realized = sum(p.realized_pnl_usd or 0.0 for p in closed_positions)

    cash = starting_capital_usd + realized - invested - fees_paid_usd
    equity = cash + market_value

    day_start_equity = starting_capital_usd + (realized - realized_today_usd)
    today_pnl = equity - day_start_equity

    wins = sum(1 for p in closed_positions if (p.realized_pnl_usd or 0.0) > 0)
    losses = sum(1 for p in closed_positions if (p.realized_pnl_usd or 0.0) < 0)

    return Portfolio(
        starting_capital_usd=starting_capital_usd,
        cash_usd=round(cash, 4),
        invested_usd=round(invested, 4),
        market_value_usd=round(market_value, 4),
        equity_usd=round(equity, 4),
        realized_pnl_usd=round(realized, 4),
        unrealized_pnl_usd=round(unrealized, 4),
        realized_today_usd=round(realized_today_usd, 4),
        today_pnl_usd=round(today_pnl, 4),
        open_positions=len(open_positions),
        total_trades=len(closed_positions),
        wins=wins,
        losses=losses,
    )
