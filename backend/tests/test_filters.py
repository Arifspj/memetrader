from datetime import UTC, datetime, timedelta

from app.engine.filters import run_safety_filters
from tests.factories import make_snapshot

LIMITS = {"min_liquidity_usd": 50_000, "min_volume_5m_usd": 20_000}


def test_clean_token_passes():
    report = run_safety_filters(make_snapshot(), **LIMITS)
    assert report.passed
    assert report.flags == []
    assert report.score == 100.0


def test_low_liquidity_flagged():
    report = run_safety_filters(make_snapshot(liquidity_usd=5_000), **LIMITS)
    assert "low_liquidity" in report.flags
    assert not report.passed


def test_sell_pressure_flagged():
    report = run_safety_filters(make_snapshot(txns_5m_buys=10, txns_5m_sells=90), **LIMITS)
    assert "sell_pressure" in report.flags


def test_vertical_pump_flagged():
    report = run_safety_filters(make_snapshot(price_change_5m=650.0), **LIMITS)
    assert "vertical_pump" in report.flags


def test_fresh_launch_penalised():
    snap = make_snapshot(pair_created_at=datetime.now(UTC) - timedelta(seconds=20))
    report = run_safety_filters(snap, **LIMITS)
    assert "pair_too_new" in report.flags


def test_url_in_metadata_flagged():
    report = run_safety_filters(make_snapshot(symbol="FREE", name="visit http://x.io"), **LIMITS)
    assert "suspicious_metadata" in report.flags


def test_holder_concentration_flagged():
    report = run_safety_filters(
        make_snapshot(),
        holder_stats={"holders": 30, "top10_pct": 85, "concentrated": True},
        **LIMITS,
    )
    assert "holder_concentration" in report.flags
    assert not report.passed


def test_zero_price_is_hard_fail():
    report = run_safety_filters(make_snapshot(price_usd=0.0), **LIMITS)
    assert not report.passed
    assert "invalid_price" in report.flags
