from app.engine.exits import evaluate_exit
from app.engine.exits_params import ExitParams
from app.engine.risk import RiskLimits, evaluate_buy, position_size_usd, trailing_stop_for
from app.engine.types import Candidate, ExitReason, SafetyReport, ScoreBreakdown
from tests.factories import make_snapshot

PARAMS = ExitParams(
    take_profit_pct=12.0,
    stop_loss_pct=6.0,
    trailing_activation_pct=8.0,
    trailing_drop_pct=4.0,
    max_hold_minutes=240,
)

LIMITS = RiskLimits(
    risk_per_trade_pct=1.0,
    max_open_positions=5,
    max_daily_loss_pct=5.0,
    min_entry_score=80.0,
    max_price_impact_bps=150.0,
    starting_capital_usd=1000.0,
)


def make_candidate(score: float = 88.0, safety_score: float = 100.0) -> Candidate:
    snap = make_snapshot()
    breakdown = ScoreBreakdown(total=score)
    safety = SafetyReport(passed=safety_score >= 50, score=safety_score)
    return Candidate(snapshot=snap, safety=safety, score=breakdown)


def test_position_size_scales_with_equity():
    assert position_size_usd(1000.0, LIMITS) == 10.0
    assert position_size_usd(10_000.0, LIMITS) == 100.0


def test_approved_buy_sizes_position():
    decision = evaluate_buy(
        make_candidate(),
        equity_usd=1000.0,
        cash_usd=1000.0,
        open_positions=0,
        realized_pnl_today=0.0,
        limits=LIMITS,
    )
    assert decision.approved
    assert decision.usd_size == 10.0


def test_low_score_is_rejected():
    decision = evaluate_buy(
        make_candidate(score=55.0),
        equity_usd=1000.0,
        cash_usd=1000.0,
        open_positions=0,
        realized_pnl_today=0.0,
        limits=LIMITS,
    )
    assert not decision.approved
    assert any("score_below" in r for r in decision.reasons)


def test_max_open_positions_blocks():
    decision = evaluate_buy(
        make_candidate(),
        equity_usd=1000.0,
        cash_usd=1000.0,
        open_positions=5,
        realized_pnl_today=0.0,
        limits=LIMITS,
    )
    assert not decision.approved
    assert "max_open_positions" in decision.reasons


def test_daily_loss_limit_halts():
    decision = evaluate_buy(
        make_candidate(),
        equity_usd=1000.0,
        cash_usd=1000.0,
        open_positions=0,
        realized_pnl_today=-60.0,
        limits=LIMITS,
    )
    assert not decision.approved
    assert decision.halt
    assert "daily_loss_limit_hit" in decision.reasons[0]


def test_price_impact_blocks():
    decision = evaluate_buy(
        make_candidate(),
        equity_usd=1000.0,
        cash_usd=1000.0,
        open_positions=0,
        realized_pnl_today=0.0,
        limits=LIMITS,
        price_impact_bps=400,
    )
    assert not decision.approved
    assert any("price_impact" in r for r in decision.reasons)


def test_no_cash_blocks():
    decision = evaluate_buy(
        make_candidate(),
        equity_usd=1000.0,
        cash_usd=1.0,
        open_positions=0,
        realized_pnl_today=0.0,
        limits=LIMITS,
    )
    assert not decision.approved


# ---------------- exits ----------------

BASE = {
    "entry_price": 1.0,
    "peak_price": 1.0,
    "stop_loss": 0.94,
    "take_profit": 1.12,
    "trailing_stop": None,
    "entry_score": 88.0,
    "current_score": 85.0,
    "current_liquidity_usd": 850_000.0,
    "entry_liquidity_usd": 850_000.0,
    "hold_minutes": 5.0,
    "params": PARAMS,
}


def exit(**overrides):
    return evaluate_exit(**{**BASE, **overrides})


def test_take_profit_fires():
    signal = exit(current_price=1.13)
    assert signal and signal.reason is ExitReason.TAKE_PROFIT


def test_stop_loss_fires():
    signal = exit(current_price=0.93)
    assert signal and signal.reason is ExitReason.STOP_LOSS


def test_whale_dump_beats_take_profit():
    signal = exit(current_price=1.5, whale_dump=True)
    assert signal and signal.reason is ExitReason.WHALE_DUMP


def test_liquidity_collapse_exits():
    signal = exit(current_price=1.02, current_liquidity_usd=100_000)
    assert signal and signal.reason is ExitReason.LIQUIDITY_COLLAPSE


def test_score_collapse_exits():
    signal = exit(current_price=1.02, current_score=50.0)
    assert signal and signal.reason is ExitReason.SCORE_COLLAPSE


def test_max_hold_exits():
    signal = exit(current_price=1.02, hold_minutes=300)
    assert signal and signal.reason is ExitReason.MAX_HOLD


def test_nothing_fires_in_the_middle():
    assert exit(current_price=1.05) is None


def test_trailing_stop_only_activates_after_threshold():
    assert trailing_stop_for(1.0, 1.05, activation_pct=8.0, drop_pct=4.0) is None
    trail = trailing_stop_for(1.0, 1.10, activation_pct=8.0, drop_pct=4.0)
    assert trail == round(1.10 * 0.96, 12)


def test_trailing_stop_exit():
    trail = trailing_stop_for(1.0, 1.10, activation_pct=8.0, drop_pct=4.0)
    signal = exit(current_price=1.05, peak_price=1.10, trailing_stop=trail)
    assert signal and signal.reason is ExitReason.TRAILING_STOP
