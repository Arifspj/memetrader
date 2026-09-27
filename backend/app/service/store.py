"""All bot persistence in one place, so the engine loop stays readable."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.engine.pnl import Portfolio, compute_portfolio, start_of_utc_day
from app.engine.types import ExitReason, FillResult, TokenSnapshot
from app.models import (
    BotEvent,
    BotRun,
    BotSettings,
    EquitySnapshot,
    Position,
    Token,
    Trade,
    User,
    utcnow,
)


def _aware(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value if value.tzinfo else value.replace(tzinfo=UTC)


class Store:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    # ---------------- users / settings ----------------

    async def get_or_create_user(self, wallet_address: str) -> User:
        user = await self.session.scalar(select(User).where(User.wallet_address == wallet_address))
        if user:
            return user
        user = User(wallet_address=wallet_address)
        self.session.add(user)
        await self.session.flush()
        self.session.add(BotSettings(user_id=user.id))
        await self.session.flush()
        return user

    async def settings(self, user_id: str) -> BotSettings:
        row = await self.session.scalar(select(BotSettings).where(BotSettings.user_id == user_id))
        if row is None:
            row = BotSettings(user_id=user_id)
            self.session.add(row)
            await self.session.flush()
        return row

    async def update_settings(self, user_id: str, values: dict) -> BotSettings:
        row = await self.settings(user_id)
        for key, value in values.items():
            if value is not None:
                setattr(row, key, value)
        await self.session.flush()
        return row

    # ---------------- runs ----------------

    async def start_run(self, user_id: str, mode: str) -> BotRun:
        run = BotRun(
            user_id=user_id,
            status="running",
            mode=mode,
            started_at=utcnow(),
            last_heartbeat=utcnow(),
        )
        self.session.add(run)
        await self.session.flush()
        return run

    async def stop_run(self, run_id: str, error: str | None = None) -> None:
        run = await self.session.scalar(select(BotRun).where(BotRun.id == run_id))
        if run:
            run.status = "stopped"
            run.stopped_at = utcnow()
            run.error = error
            await self.session.flush()

    async def heartbeat(self, run_id: str) -> None:
        run = await self.session.scalar(select(BotRun).where(BotRun.id == run_id))
        if run:
            run.last_heartbeat = utcnow()
            await self.session.flush()

    async def active_run(self, user_id: str) -> BotRun | None:
        return await self.session.scalar(
            select(BotRun)
            .where(BotRun.user_id == user_id, BotRun.status == "running")
            .order_by(BotRun.started_at.desc())
        )

    # ---------------- tokens ----------------

    async def upsert_token(self, snap: TokenSnapshot, score: float, breakdown: dict) -> Token:
        row = await self.session.scalar(
            select(Token).where(Token.chain == snap.chain, Token.pair_address == snap.pair_address)
        )
        if row is None:
            row = Token(chain=snap.chain, pair_address=snap.pair_address, symbol=snap.symbol)
            self.session.add(row)
        row.mint = snap.mint
        row.dex_id = snap.dex_id
        row.name = snap.name
        row.image_url = snap.image_url
        row.price_usd = snap.price_usd
        row.liquidity_usd = snap.liquidity_usd
        row.volume_5m = snap.volume_5m
        row.volume_24h = snap.volume_24h
        row.price_change_5m = snap.price_change_5m
        row.price_change_1h = snap.price_change_1h
        row.price_change_24h = snap.price_change_24h
        row.txns_5m_buys = snap.txns_5m_buys
        row.txns_5m_sells = snap.txns_5m_sells
        row.pair_created_at = snap.pair_created_at
        row.last_score = score
        row.last_score_breakdown = breakdown
        row.last_seen_at = utcnow()
        await self.session.flush()
        return row

    async def top_opportunities(self, user_id: str, limit: int = 20) -> list[Token]:
        min_score = (await self.settings(user_id)).min_entry_score
        rows = await self.session.scalars(
            select(Token)
            .where(Token.chain == "solana", Token.last_score >= min_score)
            .order_by(Token.last_score.desc())
            .limit(limit)
        )
        return list(rows)

    # ---------------- positions ----------------

    async def open_positions(self, user_id: str) -> list[Position]:
        rows = await self.session.scalars(
            select(Position)
            .where(Position.user_id == user_id, Position.status == "open")
            .order_by(Position.opened_at.asc())
        )
        return list(rows)

    async def closed_positions(self, user_id: str) -> list[Position]:
        rows = await self.session.scalars(
            select(Position)
            .where(Position.user_id == user_id, Position.status == "closed")
            .order_by(Position.closed_at.desc())
        )
        return list(rows)

    async def position_by_mint(self, user_id: str, mint: str) -> Position | None:
        return await self.session.scalar(
            select(Position).where(
                Position.user_id == user_id,
                Position.mint == mint,
                Position.status == "open",
            )
        )

    async def recently_closed_mints(self, user_id: str, within_minutes: int) -> set[str]:
        """Mints that were exited recently - used to block instant re-entry."""
        if within_minutes <= 0:
            return set()
        cutoff = utcnow() - timedelta(minutes=within_minutes)
        rows = await self.session.scalars(
            select(Position.mint).where(
                Position.user_id == user_id,
                Position.status == "closed",
                Position.closed_at >= cutoff,
            )
        )
        return set(rows)

    async def record_buy(
        self,
        user_id: str,
        run_id: str | None,
        fill: FillResult,
        *,
        entry_score: float,
        reason: str,
        stop_loss: float,
        take_profit: float,
        trailing_stop: float | None = None,
        entry_liquidity_usd: float = 0.0,
    ) -> Position:
        position = Position(
            user_id=user_id,
            run_id=run_id,
            mint=fill.mint,
            pair_address=fill.pair_address,
            dex_id=fill.dex_id,
            symbol=fill.symbol,
            status="open",
            qty=fill.qty,
            entry_price=fill.price,
            invested_usd=fill.usd_amount,
            fees_usd=fill.fees_usd,
            entry_score=entry_score,
            score_at_entry=entry_score,
            entry_reason=reason,
            current_price=fill.price,
            peak_price=fill.price,
            entry_liquidity_usd=entry_liquidity_usd,
            stop_loss=stop_loss,
            take_profit=take_profit,
            trailing_stop=trailing_stop,
            opened_at=utcnow(),
        )
        self.session.add(position)
        await self.session.flush()
        return position

    async def close_position(
        self, position: Position, fill: FillResult, reason: ExitReason | str
    ) -> float:
        proceeds = fill.qty * fill.price
        pnl = proceeds - position.invested_usd
        position.status = "closed"
        position.exit_price = fill.price
        position.exit_reason = str(reason)
        position.realized_pnl_usd = round(pnl, 6)
        position.closed_at = utcnow()
        position.current_price = fill.price
        position.fees_usd = (position.fees_usd or 0.0) + fill.fees_usd
        await self.session.flush()
        return round(pnl, 6)

    async def mark_position(
        self, position: Position, price: float, trailing_stop: float | None
    ) -> None:
        position.current_price = price
        position.peak_price = max(position.peak_price or 0.0, price)
        if trailing_stop:
            position.trailing_stop = max(position.trailing_stop or 0.0, trailing_stop)
        await self.session.flush()

    # ---------------- trades / events ----------------

    async def record_trade(
        self,
        user_id: str,
        fill: FillResult,
        *,
        run_id: str | None,
        position_id: str | None,
        reason: str | None = None,
        pnl_usd: float | None = None,
        mode: str = "paper",
        status: str = "filled",
    ) -> Trade:
        trade = Trade(
            user_id=user_id,
            run_id=run_id,
            position_id=position_id,
            side=fill.side.value,
            mode=mode,
            status=status,
            mint=fill.mint,
            pair_address=fill.pair_address,
            dex_id=fill.dex_id,
            symbol=fill.symbol,
            usd_amount=fill.usd_amount,
            qty=fill.qty,
            price=fill.price,
            price_impact_bps=fill.price_impact_bps,
            tx_signature=fill.tx_signature or fill.pending_signature,
            route_summary=fill.route_summary,
            reason=reason,
            pnl_usd=pnl_usd,
        )
        self.session.add(trade)
        await self.session.flush()
        return trade

    async def log(
        self,
        user_id: str,
        message: str,
        *,
        level: str = "info",
        category: str = "system",
        symbol: str | None = None,
        payload: dict | None = None,
    ) -> BotEvent:
        event = BotEvent(
            user_id=user_id,
            level=level,
            category=category,
            symbol=symbol,
            message=message,
            payload=payload,
        )
        self.session.add(event)
        await self.session.flush()
        return event

    async def events(self, user_id: str, limit: int = 100) -> list[BotEvent]:
        rows = await self.session.scalars(
            select(BotEvent)
            .where(BotEvent.user_id == user_id)
            .order_by(BotEvent.created_at.desc())
            .limit(limit)
        )
        return list(reversed(list(rows)))

    async def trades(self, user_id: str, limit: int = 100) -> list[Trade]:
        rows = await self.session.scalars(
            select(Trade)
            .where(Trade.user_id == user_id)
            .order_by(Trade.created_at.desc())
            .limit(limit)
        )
        return list(rows)

    async def trades_today(self, user_id: str) -> int:
        since = start_of_utc_day()
        return (
            await self.session.scalar(
                select(func.count(Trade.id)).where(
                    Trade.user_id == user_id, Trade.created_at >= since
                )
            )
            or 0
        )

    # ---------------- portfolio ----------------

    async def realized_today(self, user_id: str) -> float:
        since = start_of_utc_day()
        rows = await self.session.scalars(
            select(Position).where(
                Position.user_id == user_id,
                Position.status == "closed",
                Position.closed_at >= since,
            )
        )
        return round(sum(p.realized_pnl_usd or 0.0 for p in rows), 6)

    async def fees_paid(self, user_id: str) -> float:
        return round(
            sum((p.fees_usd or 0.0) for p in await self.open_positions(user_id))
            + await self.closed_fees(user_id),
            6,
        )

    async def portfolio(self, user_id: str) -> Portfolio:
        settings_row = await self.settings(user_id)
        return await self.portfolio_with(user_id, settings_row.starting_capital_usd)

    async def portfolio_with(self, user_id: str, starting_capital: float) -> Portfolio:
        open_positions = await self.open_positions(user_id)
        closed_positions = await self.closed_positions(user_id)
        realized_today = await self.realized_today(user_id)
        fees = sum((p.fees_usd or 0.0) for p in open_positions) + await self.closed_fees(user_id)
        return compute_portfolio(
            starting_capital_usd=starting_capital,
            open_positions=open_positions,
            closed_positions=closed_positions,
            realized_today_usd=realized_today,
            fees_paid_usd=fees,
        )

    async def closed_fees(self, user_id: str) -> float:
        rows = await self.session.scalars(
            select(Position).where(Position.user_id == user_id, Position.status == "closed")
        )
        return round(sum(p.fees_usd or 0.0 for p in rows), 6)

    async def snapshot(self, user_id: str, portfolio: Portfolio) -> EquitySnapshot:
        row = EquitySnapshot(
            user_id=user_id,
            equity_usd=portfolio.equity_usd,
            cash_usd=portfolio.cash_usd,
            invested_usd=portfolio.invested_usd,
            realized_pnl_usd=portfolio.realized_pnl_usd,
            unrealized_pnl_usd=portfolio.unrealized_pnl_usd,
            open_positions=portfolio.open_positions,
        )
        self.session.add(row)
        await self.session.flush()
        return row
