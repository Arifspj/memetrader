from fastapi import APIRouter, Query

from app.deps import CurrentUser, SessionDep
from app.runtime import runtime
from app.schemas import OpportunityListOut, PortfolioOut, TokenOut
from app.service.store import Store

router = APIRouter(tags=["data"])


@router.get("/market/opportunities", response_model=OpportunityListOut)
async def opportunities(
    user: CurrentUser, session: SessionDep, limit: int = Query(default=20, ge=1, le=100)
) -> OpportunityListOut:
    store = Store(session)
    bot = runtime.bot_for(user.id)
    candidates, scanned = await bot.scanner.scan()
    tradable = [c for c in candidates if c.total_score >= bot.scanner.min_score][:limit]
    for candidate in tradable:
        await store.upsert_token(
            candidate.snapshot, candidate.total_score, candidate.score.as_dict()
        )
    await session.commit()
    return OpportunityListOut(
        scanned=scanned,
        count=len(tradable),
        items=[
            TokenOut(
                symbol=c.symbol,
                name=c.snapshot.name,
                mint=c.snapshot.mint,
                pair_address=c.snapshot.pair_address,
                dex_id=c.snapshot.dex_id,
                price_usd=c.snapshot.price_usd,
                liquidity_usd=c.snapshot.liquidity_usd,
                volume_5m=c.snapshot.volume_5m,
                price_change_5m=c.snapshot.price_change_5m,
                buy_sell_ratio=round(c.snapshot.buy_sell_ratio, 3),
                score=c.total_score,
                blocked_reasons=c.blocked_reasons,
                score_breakdown=c.score.as_dict(),
            )
            for c in tradable
        ],
    )


@router.get("/portfolio", response_model=PortfolioOut)
async def portfolio(user: CurrentUser, session: SessionDep) -> PortfolioOut:
    p = await Store(session).portfolio(user.id)
    return PortfolioOut(
        equity_usd=p.equity_usd,
        cash_usd=p.cash_usd,
        invested_usd=p.invested_usd,
        realized_pnl_usd=p.realized_pnl_usd,
        unrealized_pnl_usd=p.unrealized_pnl_usd,
        today_pnl_usd=p.today_pnl_usd,
        today_pnl_pct=p.today_pnl_pct,
        open_positions=p.open_positions,
        total_trades=p.total_trades,
        wins=p.wins,
        losses=p.losses,
        win_rate=p.win_rate,
        starting_capital_usd=p.starting_capital_usd,
    )
