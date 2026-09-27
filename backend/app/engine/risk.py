"""Risk engine: the last gate before any BUY is allowed.

Pure functions, no I/O - so every rule below is unit testable.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.engine.types import Candidate, RiskDecision

MAX_SINGLE_POSITION_PCT = 25.0
MIN_TRADE_USD = 5.0


@dataclass(slots=True)
class RiskLimits:
    risk_per_trade_pct: float
    max_open_positions: int
    max_daily_loss_pct: float
    min_entry_score: float
    max_price_impact_bps: float
    starting_capital_usd: float


def position_size_usd(equity_usd: float, limits: RiskLimits) -> float:
    size = equity_usd * (limits.risk_per_trade_pct / 100.0)
    cap = equity_usd * (MAX_SINGLE_POSITION_PCT / 100.0)
    return round(min(size, cap), 2)


def daily_pnl_pct(realized_today: float, equity_usd: float) -> float:
    if equity_usd <= 0:
        return 0.0
    return (realized_today / equity_usd) * 100.0


def evaluate_buy(
    candidate: Candidate,
    *,
    equity_usd: float,
    cash_usd: float,
    open_positions: int,
    realized_pnl_today: float,
    limits: RiskLimits,
    price_impact_bps: float | None = None,
) -> RiskDecision:
    reasons: list[str] = []

    loss_pct = daily_pnl_pct(realized_pnl_today, equity_usd)
    if loss_pct <= -abs(limits.max_daily_loss_pct):
        return RiskDecision(
            approved=False,
            usd_size=0.0,
            reasons=[f"daily_loss_limit_hit:{loss_pct:.2f}%"],
            halt=True,
        )

    if candidate.blocked_reasons:
        reasons.extend(candidate.blocked_reasons)
    if not candidate.safety.passed:
        reasons.append("safety_failed")
    if candidate.total_score < limits.min_entry_score:
        reasons.append(f"score_below_{limits.min_entry_score:.0f}")
    if open_positions >= limits.max_open_positions:
        reasons.append("max_open_positions")
    if equity_usd <= 0:
        reasons.append("no_equity")
    if price_impact_bps is not None and price_impact_bps > limits.max_price_impact_bps:
        reasons.append(f"price_impact_{price_impact_bps:.0f}bps")

    size = position_size_usd(equity_usd, limits)
    if cash_usd < MIN_TRADE_USD:
        reasons.append("no_cash")
    size = min(size, cash_usd)
    if size < MIN_TRADE_USD:
        reasons.append("size_below_min")

    if reasons:
        return RiskDecision(approved=False, usd_size=0.0, reasons=reasons)
    return RiskDecision(approved=True, usd_size=round(size, 2), reasons=[])


def can_open_more(open_positions: int, limits: RiskLimits) -> bool:
    return open_positions < limits.max_open_positions


def trailing_stop_for(
    entry_price: float,
    peak_price: float,
    activation_pct: float,
    drop_pct: float,
) -> float | None:
    """Ratchet stop that only ever moves up, never down."""
    activation_price = entry_price * (1 + activation_pct / 100.0)
    if peak_price < activation_price:
        return None
    return round(peak_price * (1 - drop_pct / 100.0), 12)
