"""Hard safety filters. Anything that fails here never reaches the entry engine."""

from __future__ import annotations

import re

from app.engine.types import SafetyReport, TokenSnapshot

SCAM_WORDS = (
    "scam",
    "rug",
    "honeypot",
    "pump.fun.ceo",
    "free claim",
    "airdrop link",
    "visit http",
    "bot reward",
)
URL_RE = re.compile(r"https?://|www\.|\.com|\.io|\.xyz|\.fun", re.IGNORECASE)

# A pair younger than this is usually a fresh launch with no track record.
MIN_PAIR_AGE_MINUTES = 2.0
# 5m pump beyond this is a classic exit-liquidity trap.
MAX_PUMP_5M_PCT = 300.0
MIN_BUY_SELL_RATIO = 1.0


def run_safety_filters(
    snap: TokenSnapshot,
    *,
    min_liquidity_usd: float,
    min_volume_5m_usd: float,
    holder_stats: dict | None = None,
) -> SafetyReport:
    report = SafetyReport(passed=True, score=100.0)

    if snap.price_usd <= 0:
        report.block("invalid_price", 100.0)
    if not snap.mint:
        report.block("missing_mint", 100.0)
    if snap.liquidity_usd < min_liquidity_usd:
        report.block("low_liquidity", 25.0)
    if snap.volume_5m < min_volume_5m_usd:
        report.block("low_volume_5m", 20.0)
    if snap.buy_sell_ratio < MIN_BUY_SELL_RATIO:
        report.add("sell_pressure", 15.0)

    age = snap.age_minutes
    if age is not None and age < MIN_PAIR_AGE_MINUTES:
        report.add("pair_too_new", 20.0)

    if snap.price_change_5m > MAX_PUMP_5M_PCT:
        report.block("vertical_pump", 30.0)
    if snap.price_change_24h < -60:
        report.add("free_fall", 25.0)

    text = f"{snap.symbol} {snap.name or ''}"
    if any(word in text.lower() for word in SCAM_WORDS) or URL_RE.search(text):
        report.add("suspicious_metadata", 35.0)

    if holder_stats:
        if holder_stats.get("concentrated"):
            report.block("holder_concentration", 30.0)
        if (holder_stats.get("holders") or 0) < 50:
            report.add("too_few_holders", 20.0)

    report.passed = not report.blocking and report.score >= 50.0
    return report
