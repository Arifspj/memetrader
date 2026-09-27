"""Exit engine: TP / SL / trailing / AI signal / emergency.

Order matters. Emergency conditions win over take-profit, and stop-loss is
checked before take-profit so a single candle that spans both exits at the SL.
"""

from __future__ import annotations

from app.engine.exits_params import ExitParams
from app.engine.types import ExitReason, ExitSignal

# liquidity below this fraction of entry liquidity = "liquidity collapse"
LIQUIDITY_COLLAPSE_RATIO = 0.45
# score drop of this many points from entry = thesis invalidated
SCORE_COLLAPSE_DELTA = 30.0
# unrealized loss at which we stop waiting for a bounce
DEEP_LOSS_PCT = -18.0


def evaluate_exit(
    *,
    entry_price: float,
    current_price: float,
    peak_price: float,
    stop_loss: float,
    take_profit: float,
    trailing_stop: float | None,
    entry_score: float,
    current_score: float | None,
    current_liquidity_usd: float | None,
    entry_liquidity_usd: float | None,
    hold_minutes: float,
    whale_dump: bool = False,
    params: ExitParams,
) -> ExitSignal | None:
    if current_price <= 0:
        return None

    pnl_pct = (current_price / entry_price - 1) * 100

    # 1. emergency
    if whale_dump:
        return ExitSignal(ExitReason.WHALE_DUMP, current_price, "whale distribution detected")
    if (
        current_liquidity_usd is not None
        and entry_liquidity_usd
        and current_liquidity_usd < entry_liquidity_usd * LIQUIDITY_COLLAPSE_RATIO
    ):
        return ExitSignal(
            ExitReason.LIQUIDITY_COLLAPSE,
            current_price,
            f"liquidity {current_liquidity_usd:,.0f} vs {entry_liquidity_usd:,.0f}",
        )

    # 2. stop loss / trailing (protective first)
    if trailing_stop and current_price <= trailing_stop:
        return ExitSignal(ExitReason.TRAILING_STOP, current_price, f"trailing {trailing_stop:.12g}")
    if current_price <= stop_loss:
        return ExitSignal(ExitReason.STOP_LOSS, current_price, f"stop {stop_loss:.12g}")
    if pnl_pct <= DEEP_LOSS_PCT:
        return ExitSignal(ExitReason.AI_SIGNAL, current_price, f"deep loss {pnl_pct:.1f}%")

    # 3. take profit
    if current_price >= take_profit:
        return ExitSignal(ExitReason.TAKE_PROFIT, current_price, f"tp {take_profit:.12g}")

    # 4. thesis invalidation
    if current_score is not None and entry_score - current_score >= SCORE_COLLAPSE_DELTA:
        return ExitSignal(
            ExitReason.SCORE_COLLAPSE,
            current_price,
            f"score {current_score:.0f} from {entry_score:.0f}",
        )

    # 5. time stop
    if hold_minutes >= params.max_hold_minutes:
        return ExitSignal(ExitReason.MAX_HOLD, current_price, f"held {hold_minutes:.0f}m")

    return None
