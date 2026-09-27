from fastapi import APIRouter, Query

from app.deps import CurrentUser, SessionDep
from app.engine.pnl import unrealized_pnl, unrealized_pnl_pct
from app.schemas import EventOut, PositionOut, TradeOut
from app.service.store import Store

router = APIRouter(tags=["positions"])


@router.get("/positions", response_model=list[PositionOut])
async def positions(
    user: CurrentUser, session: SessionDep, status: str = Query(default="open")
) -> list[PositionOut]:
    store = Store(session)
    rows = (
        await store.open_positions(user.id)
        if status == "open"
        else await store.closed_positions(user.id)
    )
    return [
        PositionOut(
            id=p.id,
            symbol=p.symbol,
            name=p.name,
            mint=p.mint,
            status=p.status,
            qty=p.qty,
            entry_price=p.entry_price,
            current_price=p.current_price,
            invested_usd=p.invested_usd,
            entry_score=p.entry_score,
            stop_loss=p.stop_loss,
            take_profit=p.take_profit,
            trailing_stop=p.trailing_stop,
            unrealized_pnl_usd=round(unrealized_pnl(p), 4),
            unrealized_pnl_pct=unrealized_pnl_pct(p),
            opened_at=p.opened_at,
            closed_at=p.closed_at,
            exit_price=p.exit_price,
            exit_reason=p.exit_reason,
            realized_pnl_usd=p.realized_pnl_usd,
        )
        for p in rows
    ]


@router.get("/trades", response_model=list[TradeOut])
async def trades(
    user: CurrentUser, session: SessionDep, limit: int = Query(default=100, ge=1, le=500)
) -> list[TradeOut]:
    return [TradeOut.model_validate(t) for t in await Store(session).trades(user.id, limit)]


@router.get("/logs", response_model=list[EventOut])
async def logs(
    user: CurrentUser, session: SessionDep, limit: int = Query(default=100, ge=1, le=500)
) -> list[EventOut]:
    return [EventOut.model_validate(e) for e in await Store(session).events(user.id, limit)]
