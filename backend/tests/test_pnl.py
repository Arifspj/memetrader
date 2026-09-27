from types import SimpleNamespace

from app.engine.pnl import compute_portfolio, start_of_utc_day, unrealized_pnl_pct


def position(**kwargs):
    base = {
        "invested_usd": 100.0,
        "qty": 1000.0,
        "entry_price": 0.1,
        "current_price": 0.1,
        "realized_pnl_usd": None,
        "fees_usd": 0.0,
    }
    base.update(kwargs)
    return SimpleNamespace(**base)


def test_flat_portfolio():
    p = compute_portfolio(starting_capital_usd=1000.0, open_positions=[], closed_positions=[])
    assert p.equity_usd == 1000.0
    assert p.cash_usd == 1000.0
    assert p.today_pnl_usd == 0.0
    assert p.win_rate is None


def test_open_position_moves_equity():
    p = compute_portfolio(
        starting_capital_usd=1000.0,
        open_positions=[position(current_price=0.12)],
        closed_positions=[],
    )
    assert p.invested_usd == 100.0
    assert p.market_value_usd == 120.0
    assert p.unrealized_pnl_usd == 20.0
    assert p.equity_usd == 1020.0
    assert p.cash_usd == 900.0


def test_realized_pnl_moves_cash():
    closed = position(status="closed", realized_pnl_usd=15.0, fees_usd=0.4)
    p = compute_portfolio(
        starting_capital_usd=1000.0, open_positions=[], closed_positions=[closed], fees_paid_usd=0.4
    )
    assert p.realized_pnl_usd == 15.0
    assert p.equity_usd == 1014.6
    assert p.wins == 1
    assert p.win_rate == 100.0


def test_win_rate_counts_both_sides():
    closed = [
        position(realized_pnl_usd=10.0),
        position(realized_pnl_usd=-4.0),
        position(realized_pnl_usd=-1.0),
    ]
    p = compute_portfolio(starting_capital_usd=1000.0, open_positions=[], closed_positions=closed)
    assert (p.wins, p.losses) == (1, 2)
    assert p.win_rate == 33.33


def test_profit_closed_before_today_is_not_todays_pnl():
    p = compute_portfolio(
        starting_capital_usd=1000.0,
        open_positions=[],
        closed_positions=[position(realized_pnl_usd=50.0)],
        realized_today_usd=0.0,
    )
    assert p.equity_usd == 1050.0
    assert p.today_pnl_usd == 0.0


def test_profit_closed_today_counts_towards_today():
    p = compute_portfolio(
        starting_capital_usd=1000.0,
        open_positions=[],
        closed_positions=[position(realized_pnl_usd=50.0)],
        realized_today_usd=50.0,
    )
    assert p.today_pnl_usd == 50.0
    assert p.today_pnl_pct == 5.0


def test_unrealized_pct():
    assert unrealized_pnl_pct(position(current_price=0.11)) == 10.0
    assert unrealized_pnl_pct(position(invested_usd=0.0)) == 0.0


def test_start_of_day_is_midnight_utc():
    assert start_of_utc_day().hour == 0
