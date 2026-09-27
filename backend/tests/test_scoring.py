from app.engine.filters import run_safety_filters
from app.engine.scoring import WEIGHTS, log_scale, score_token
from tests.factories import make_snapshot


def test_weights_sum_to_100():
    assert sum(WEIGHTS.values()) == 100.0


def test_log_scale_bounds():
    assert log_scale(10_000, 10_000, 2_000_000) == 0.0
    assert log_scale(2_000_000, 10_000, 2_000_000) == 100.0
    assert 0 < log_scale(100_000, 10_000, 2_000_000) < 100


def test_strong_token_scores_high():
    snap = make_snapshot()
    safety = run_safety_filters(snap, min_liquidity_usd=50_000, min_volume_5m_usd=20_000)
    score = score_token(snap, safety, holder_stats={"holders": 2_000, "top10_pct": 22})
    assert safety.passed
    assert score.total > 70
    assert 0 <= score.total <= 100


def test_weak_token_scores_lower():
    good = make_snapshot()
    weak = make_snapshot(
        pair_address="PAIR2",
        mint="MINT2",
        liquidity_usd=60_000,
        volume_5m=25_000,
        price_change_5m=-3.0,
        price_change_1h=-8.0,
        txns_5m_buys=40,
        txns_5m_sells=120,
    )
    g = score_token(
        good, run_safety_filters(good, min_liquidity_usd=50_000, min_volume_5m_usd=20_000)
    )
    w = score_token(
        weak, run_safety_filters(weak, min_liquidity_usd=50_000, min_volume_5m_usd=20_000)
    )
    assert g.total > w.total


def test_volume_acceleration_uses_previous_scan():
    snap = make_snapshot()
    safety = run_safety_filters(snap, min_liquidity_usd=50_000, min_volume_5m_usd=20_000)
    flat = score_token(snap, safety, prev_volume_5m=320_000)
    accelerating = score_token(snap, safety, prev_volume_5m=40_000)
    assert accelerating.volume_accel > flat.volume_accel
