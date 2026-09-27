"""Opportunity scoring, 0-100. Deterministic, no LLM in the hot path.

liquidity            15
volume acceleration  15
momentum             15
buy pressure         10
whale activity       15
holder activity      10
market conditions    10
safety               10
                    ----
                    100
"""

from __future__ import annotations

import math

from app.engine.types import SafetyReport, ScoreBreakdown, TokenSnapshot

WEIGHTS = {
    "liquidity": 15.0,
    "volume_accel": 15.0,
    "momentum": 15.0,
    "buy_pressure": 10.0,
    "whale": 15.0,
    "holder": 10.0,
    "market": 10.0,
    "safety": 10.0,
}

NEUTRAL = 50.0


def clamp(value: float, low: float = 0.0, high: float = 100.0) -> float:
    return max(low, min(high, value))


def log_scale(value: float, floor: float, ceiling: float) -> float:
    """Map value in [floor, ceiling] onto 0-100 logarithmically."""
    if value <= floor or ceiling <= floor:
        return 0.0
    return clamp(100.0 * math.log(value / floor) / math.log(ceiling / floor))


def score_liquidity(snap: TokenSnapshot) -> float:
    # 10k -> 0, 250k -> 62, 1m -> 84, 2m+ -> 100
    return log_scale(snap.liquidity_usd, 10_000, 2_000_000)


def score_volume(snap: TokenSnapshot, prev_volume_5m: float | None = None) -> float:
    ratio_score = log_scale(snap.volume_liquidity_ratio, 0.05, 3.0)
    if prev_volume_5m and prev_volume_5m > 0:
        growth = snap.volume_5m / prev_volume_5m
        accel_score = clamp(50.0 + 50.0 * math.tanh(math.log(max(growth, 1e-6)) / math.log(4.0)))
        return 0.6 * ratio_score + 0.4 * accel_score
    return ratio_score


def score_momentum(snap: TokenSnapshot) -> float:
    if snap.price_change_1h == 0 and snap.price_change_5m == 0:
        return NEUTRAL
    blended = 0.5 * snap.price_change_5m + 0.3 * snap.price_change_1h + 0.2 * snap.price_change_24h
    return clamp(50.0 + blended * 1.2)


def score_buy_pressure(snap: TokenSnapshot) -> float:
    ratio = snap.buy_sell_ratio
    if snap.txns_5m_buys + snap.txns_5m_sells < 10:
        return NEUTRAL
    return clamp(100.0 * (ratio / (ratio + 1.0)) * 1.35)


def score_whale(snap: TokenSnapshot, holder_stats: dict | None = None) -> float:
    if not holder_stats:
        return NEUTRAL
    holders = float(holder_stats.get("holders") or 0)
    concentration = float(holder_stats.get("top10_pct") or 0.0)
    base = log_scale(holders, 50, 5_000)
    # moderate concentration is healthy, >60% is dangerous
    spread_penalty = 0.0 if concentration <= 60 else (concentration - 60) * 1.5
    return clamp(base - spread_penalty)


def score_holder(holder_stats: dict | None = None) -> float:
    if not holder_stats:
        return NEUTRAL
    holders = float(holder_stats.get("holders") or 0)
    return log_scale(holders, 50, 10_000)


def score_market(market_score: float) -> float:
    return clamp(market_score)


def score_safety(safety: SafetyReport) -> float:
    return clamp(safety.score)


def score_token(
    snap: TokenSnapshot,
    safety: SafetyReport,
    *,
    prev_volume_5m: float | None = None,
    holder_stats: dict | None = None,
    market_score: float = NEUTRAL,
) -> ScoreBreakdown:
    breakdown = ScoreBreakdown(
        liquidity=score_liquidity(snap) * WEIGHTS["liquidity"] / 100,
        volume_accel=score_volume(snap, prev_volume_5m) * WEIGHTS["volume_accel"] / 100,
        momentum=score_momentum(snap) * WEIGHTS["momentum"] / 100,
        buy_pressure=score_buy_pressure(snap) * WEIGHTS["buy_pressure"] / 100,
        whale=score_whale(snap, holder_stats) * WEIGHTS["whale"] / 100,
        holder=score_holder(holder_stats) * WEIGHTS["holder"] / 100,
        market=score_market(market_score) * WEIGHTS["market"] / 100,
        safety=score_safety(safety) * WEIGHTS["safety"] / 100,
    )
    breakdown.total = round(
        breakdown.liquidity
        + breakdown.volume_accel
        + breakdown.momentum
        + breakdown.buy_pressure
        + breakdown.whale
        + breakdown.holder
        + breakdown.market
        + breakdown.safety,
        2,
    )
    return breakdown
