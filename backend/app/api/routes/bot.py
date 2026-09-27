from fastapi import APIRouter, HTTPException

from app.deps import CurrentUser, SessionDep
from app.runtime import runtime
from app.schemas import (
    BotStateOut,
    CloseAllRequest,
    SettingsOut,
    SettingsUpdate,
)
from app.service.store import Store

router = APIRouter(prefix="/bot", tags=["bot"])


def _state_out(bot, portfolio, trades_today: int) -> BotStateOut:
    return BotStateOut(
        state=bot.status.state.value,
        mode=bot.mode,
        run_id=bot.status.run_id,
        started_at=bot.status.started_at,
        last_heartbeat=None,
        scanning=bot.status.scanning,
        tokens_scanned=bot.status.tokens_scanned,
        opportunities=bot.status.opportunities,
        open_positions=bot.status.open_positions,
        equity_usd=portfolio.equity_usd,
        today_pnl_usd=portfolio.today_pnl_usd,
        today_trades=trades_today,
        win_rate=portfolio.win_rate,
    )


@router.get("/state", response_model=BotStateOut)
async def state(user: CurrentUser, session: SessionDep) -> BotStateOut:
    store = Store(session)
    bot = runtime.bot_for(user.id)
    portfolio = await store.portfolio(user.id)
    return _state_out(bot, portfolio, await store.trades_today(user.id))


@router.post("/start", response_model=BotStateOut)
async def start(user: CurrentUser, session: SessionDep) -> BotStateOut:
    store = Store(session)
    bot = runtime.bot_for(user.id)
    await bot.start(user.id, user.wallet_address)
    portfolio = await store.portfolio(user.id)
    return _state_out(bot, portfolio, await store.trades_today(user.id))


@router.post("/stop", response_model=BotStateOut)
async def stop(user: CurrentUser, session: SessionDep) -> BotStateOut:
    """Stops new BUYs. Open positions keep their TP/SL/trailing management."""
    store = Store(session)
    bot = runtime.bot_for(user.id)
    if not bot.is_running:
        raise HTTPException(409, "bot is not running")
    await bot.stop(user.id)
    portfolio = await store.portfolio(user.id)
    return _state_out(bot, portfolio, await store.trades_today(user.id))


@router.post("/close-all")
async def close_all(
    user: CurrentUser, session: SessionDep, payload: CloseAllRequest | None = None
) -> dict:
    bot = runtime.bot_for(user.id)
    accepted = await bot.request_close_all()
    if not accepted:
        raise HTTPException(409, "bot is not running, start it to manage positions")
    await Store(session).log(
        user.id,
        "CLOSE ALL requested",
        level="warning",
        category="system",
        payload=payload.model_dump() if payload else {},
    )
    await session.commit()
    return {"accepted": accepted}


@router.get("/pending-tx")
async def pending_tx(user: CurrentUser) -> dict:
    """Unsigned Jupiter transactions waiting for the app to sign with Phantom."""
    bot = runtime.bot_for(user.id)
    return {"mode": bot.mode, "items": bot.status.pending_txs}


@router.get("/settings", response_model=SettingsOut)
async def get_settings(user: CurrentUser, session: SessionDep) -> SettingsOut:
    return SettingsOut.model_validate(await Store(session).settings(user.id))


@router.put("/settings", response_model=SettingsOut)
async def put_settings(
    user: CurrentUser, session: SessionDep, payload: SettingsUpdate
) -> SettingsOut:
    store = Store(session)
    row = await store.update_settings(user.id, payload.model_dump(exclude_none=True))
    await session.commit()
    return SettingsOut.model_validate(row)
