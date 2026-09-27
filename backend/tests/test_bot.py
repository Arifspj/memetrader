"""End-to-end bot loop: SCAN -> BUY -> MONITOR -> TP/SL -> SELL.

DexScreener is mocked, execution is paper. No API keys, no wallet, no chain.
The background loop is parked (see SCAN_INTERVAL_SECONDS in conftest) so each
test drives `tick()` explicitly and stays deterministic.
"""

from __future__ import annotations

import uuid

import httpx
import pytest
import respx

from app.engine.bot import TradingBot
from app.engine.scanner import Scanner
from app.execution.paper import PaperExecutor
from app.service.store import Store

MINT = "So11111111111111111111111111111111111111199"
PAIR = "PAIR_MEME"
WALLET = "Wallet1111111111111111111111111111111111"


def pair_payload(price: float, *, liquidity: float = 850_000, change_5m: float = 18.0) -> dict:
    return {
        "chainId": "solana",
        "dexId": "raydium",
        "pairAddress": PAIR,
        "baseToken": {"address": MINT, "symbol": "MEME", "name": "Meme Coin"},
        "quoteToken": {
            "symbol": "SOL",
            "address": "So11111111111111111111111111111111111111112",
        },
        "priceUsd": str(price),
        "liquidity": {"usd": liquidity},
        "volume": {"m5": "320000", "h24": "4000000"},
        "priceChange": {"m5": str(change_5m), "h1": "45", "h24": "120"},
        "txns": {"m5": {"buys": 184, "sells": 100}},
        "pairCreatedAt": 1750000000000,
    }


MARKET: dict = {"price": 0.0000124, "liquidity": 850_000, "change_5m": 18.0}


def _market_response(_request: httpx.Request) -> httpx.Response:
    return httpx.Response(
        200,
        json={
            "pairs": [
                pair_payload(
                    MARKET["price"],
                    liquidity=MARKET["liquidity"],
                    change_5m=MARKET["change_5m"],
                )
            ]
        },
    )


@pytest.fixture
def market():
    """Register the DexScreener routes once, then move the market per tick."""

    def _respond(request: httpx.Request) -> httpx.Response:
        return _market_response(request)

    respx.get(url__regex=r".*token-boosts/(latest|top)/v1.*").mock(
        return_value=httpx.Response(200, json=[{"chainId": "solana", "tokenAddress": MINT}])
    )
    for pattern in (r".*/latest/dex/tokens/.*", r".*/latest/dex/pairs/solana/.*"):
        respx.get(url__regex=pattern).mock(side_effect=_respond)

    def _set(price: float, *, liquidity: float = 850_000, change_5m: float = 18.0) -> None:
        MARKET.update(price=price, liquidity=liquidity, change_5m=change_5m)

    _set(0.0000124)
    yield _set
    MARKET.update(price=0.0000124, liquidity=850_000, change_5m=18.0)


@pytest.fixture
async def user(session_factory):
    wallet = f"{WALLET[:8]}{uuid.uuid4().hex[:24]}"
    async with session_factory() as session:
        store = Store(session)
        row = await store.get_or_create_user(wallet)
        settings_row = await store.settings(row.id)
        settings_row.starting_capital_usd = 1000.0
        settings_row.min_entry_score = 60.0
        settings_row.risk_per_trade_pct = 10.0
        settings_row.max_open_positions = 5
        await session.commit()
        return row.id, wallet


@pytest.fixture
async def bot(session_factory):
    from app.clients.dexscreener import DexScreenerClient

    dex = DexScreenerClient()
    scanner = Scanner(dex, None, min_liquidity_usd=50_000, min_volume_5m_usd=20_000, min_score=0)
    instance = TradingBot(session_factory, scanner, PaperExecutor(), mode="paper")
    yield instance
    await instance.shutdown()


@respx.mock
async def test_bot_opens_a_position_with_protective_levels(bot, user, market):
    market(0.0000124)
    user_id, wallet = user

    await bot.start(user_id, wallet)
    await bot.tick(user_id)

    async with bot.session_factory() as session:
        store = Store(session)
        positions = await store.open_positions(user_id)
        assert len(positions) == 1
        position = positions[0]
        assert position.symbol == "MEME"
        assert position.qty > 0
        assert position.entry_price > 0
        assert position.stop_loss < position.entry_price < position.take_profit
        assert position.entry_liquidity_usd == 850_000
        assert any(e.category == "entry" for e in await store.events(user_id))


@respx.mock
async def test_take_profit_closes_position(bot, user, market):
    user_id, wallet = user
    market(0.0000124)
    await bot.start(user_id, wallet)
    await bot.tick(user_id)

    market(0.0000161)  # +30%
    await bot.tick(user_id)

    async with bot.session_factory() as session:
        store = Store(session)
        assert (await store.open_positions(user_id)) == []
        closed = await store.closed_positions(user_id)
        assert len(closed) == 1
        assert closed[0].exit_reason == "tp"
        assert closed[0].realized_pnl_usd > 0
        assert any(e.category == "exit" for e in await store.events(user_id))


@respx.mock
async def test_stop_loss_closes_position(bot, user, market):
    user_id, wallet = user
    market(0.0000124)
    await bot.start(user_id, wallet)
    await bot.tick(user_id)

    market(0.0000105, change_5m=-40.0)  # -15%
    await bot.tick(user_id)

    async with bot.session_factory() as session:
        closed = await Store(session).closed_positions(user_id)
        assert len(closed) == 1
        assert closed[0].exit_reason in {"sl", "whale_dump", "liquidity_collapse"}
        assert closed[0].realized_pnl_usd < 0


@respx.mock
async def test_stop_prevents_new_entries(bot, user, market):
    user_id, wallet = user
    market(0.0000124)
    await bot.start(user_id, wallet)
    await bot.tick(user_id)
    await bot.stop(user_id)

    assert bot.status.state.value == "stopped"
    async with bot.session_factory() as session:
        assert len(await Store(session).open_positions(user_id)) == 1

    # even if the app calls tick, no new entry may be opened while stopped
    await bot.tick(user_id)
    async with bot.session_factory() as session:
        assert len(await Store(session).open_positions(user_id)) == 1


@respx.mock
async def test_close_all_liquidates_every_position(bot, user, market):
    user_id, wallet = user
    market(0.0000124)
    await bot.start(user_id, wallet)
    await bot.tick(user_id)

    assert await bot.request_close_all()
    await bot.tick(user_id)

    async with bot.session_factory() as session:
        store = Store(session)
        assert (await store.open_positions(user_id)) == []
        assert (await store.closed_positions(user_id))[0].exit_reason == "close_all"


@respx.mock
async def test_safety_filter_blocks_thin_liquidity(bot, user, market):
    user_id, wallet = user
    market(0.0000124, liquidity=5_000)
    await bot.start(user_id, wallet)
    await bot.tick(user_id)

    async with bot.session_factory() as session:
        assert (await Store(session).open_positions(user_id)) == []


@respx.mock
async def test_portfolio_accounting(bot, user, market):
    user_id, wallet = user
    market(0.0000124)
    await bot.start(user_id, wallet)
    await bot.tick(user_id)

    async with bot.session_factory() as session:
        portfolio = await Store(session).portfolio(user_id)
    assert portfolio.open_positions == 1
    assert portfolio.invested_usd == pytest.approx(100.0, rel=0.01)
    assert portfolio.cash_usd == pytest.approx(900.0, abs=1.5)
    assert portfolio.equity_usd == pytest.approx(1000.0, abs=1.5)
    assert portfolio.total_trades == 0


@respx.mock
async def test_bot_state_is_reported(bot, user, market):
    user_id, wallet = user
    market(0.0000124)
    await bot.start(user_id, wallet)
    await bot.tick(user_id)

    assert bot.status.state.value == "running"
    assert bot.status.tokens_scanned == 1
    assert bot.status.opportunities >= 1
    assert bot.status.open_positions == 1
    assert bot.status.equity_usd == pytest.approx(1000.0, abs=1.5)


@respx.mock
async def test_reentry_cooldown_blocks_immediate_rebuy(bot, user, market):
    """After a TP the bot must not immediately buy the same token again."""
    user_id, wallet = user
    market(0.0000124)
    await bot.start(user_id, wallet)
    await bot.tick(user_id)

    market(0.0000161)  # +30% -> take profit
    await bot.tick(user_id)

    async with bot.session_factory() as session:
        store = Store(session)
        assert (await store.open_positions(user_id)) == []
        assert (await store.closed_positions(user_id))[0].exit_reason == "tp"

    # price keeps running, but the cooldown holds the re-entry
    market(0.0000170)
    await bot.tick(user_id)
    async with bot.session_factory() as session:
        assert (await Store(session).open_positions(user_id)) == []
