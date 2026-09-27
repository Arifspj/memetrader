"""Bot orchestrator.

    START
      -> SCAN  (DexScreener boosts feed)
      -> FILTER (safety)
      -> SCORE (0-100, deterministic)
      -> RISK  (sizing + circuit breakers)
      -> BUY   (executor)
      -> MONITOR (prices, trailing ratchet)
      -> EXIT  (TP / SL / TRAIL / AI signal / emergency)
      -> SELL
      -> RESCAN ... until STOP

STOP stops new BUYs only. Open positions keep being monitored and managed.
CLOSE ALL is a separate, explicit command.

The loop owns its own DB sessions (it runs as a background task), so nothing
here depends on a request-scoped session.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from collections.abc import Callable
from dataclasses import dataclass, field

from sqlalchemy.ext.asyncio import AsyncSession

from app.engine.exits import evaluate_exit
from app.engine.exits_params import exit_params_from_settings, limits_from_settings
from app.engine.pnl import Portfolio
from app.engine.risk import evaluate_buy
from app.engine.scanner import Scanner
from app.engine.types import Candidate, ExitReason, RunState, utcnow
from app.execution.base import ExecutionError, NeedsClientSignature
from app.service.store import Store

log = logging.getLogger(__name__)

SNAPSHOT_EVERY_CYCLES = 10
HEARTBEAT_EVERY_CYCLES = 5

SessionFactory = Callable[[], AsyncSession]


@dataclass
class BotStatus:
    state: RunState = RunState.STOPPED
    run_id: str | None = None
    started_at: object | None = None
    scanning: bool = False
    tokens_scanned: int = 0
    opportunities: int = 0
    open_positions: int = 0
    equity_usd: float = 0.0
    today_pnl_usd: float = 0.0
    today_trades: int = 0
    win_rate: float | None = None
    pending_txs: list[dict] = field(default_factory=list)
    halted: bool = False
    last_error: str | None = None


class TradingBot:
    def __init__(
        self,
        session_factory: SessionFactory,
        scanner: Scanner,
        executor,
        *,
        mode: str = "paper",
    ) -> None:
        self.session_factory = session_factory
        self.scanner = scanner
        self.executor = executor
        self.mode = mode
        self.status = BotStatus()
        self.wallet_address = ""
        self._task: asyncio.Task | None = None
        self._stop_event = asyncio.Event()
        self._close_all = asyncio.Event()
        self._cycle = 0

    # ---------------- lifecycle ----------------

    @property
    def is_running(self) -> bool:
        return self.status.state is RunState.RUNNING

    async def start(self, user_id: str, wallet_address: str) -> BotStatus:
        if self.is_running:
            return self.status

        self._stop_event = asyncio.Event()
        self._close_all = asyncio.Event()
        self._cycle = 0
        self.wallet_address = wallet_address

        async with self.session_factory() as session:
            store = Store(session)
            settings_row = await store.settings(user_id)
            interval = settings_row.scan_interval_seconds
            run = await store.start_run(user_id, self.mode)
            self.status = BotStatus(
                state=RunState.RUNNING,
                run_id=run.id,
                started_at=run.started_at,
                open_positions=len(await store.open_positions(user_id)),
            )
            await store.log(
                user_id,
                f"AI TRADING STARTED ({self.mode} mode)",
                category="system",
                payload={"run_id": run.id, "mode": self.mode},
            )
            await session.commit()

        self._task = asyncio.create_task(self._loop(user_id, interval), name=f"bot-{user_id}")
        return self.status

    async def stop(self, user_id: str) -> BotStatus:
        """No new BUYs from here on. Existing positions stay monitored."""
        if not self.is_running:
            return self.status
        self._stop_event.set()
        self.status.state = RunState.STOPPED

        if self._task:
            with contextlib.suppress(TimeoutError, asyncio.CancelledError):
                await asyncio.wait_for(self._task, timeout=15)
            self._task = None

        async with self.session_factory() as session:
            store = Store(session)
            if self.status.run_id:
                await store.stop_run(self.status.run_id)
            await store.log(
                user_id,
                "AI TRADING STOPPED - no new entries, open positions still monitored",
                category="system",
            )
            self.status.open_positions = len(await store.open_positions(user_id))
            await session.commit()
        return self.status

    async def request_close_all(self) -> bool:
        if not self.is_running:
            return False
        self._close_all.set()
        return True

    async def shutdown(self) -> None:
        self._stop_event.set()
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError, TimeoutError):
                await self._task
            self._task = None

    # ---------------- main loop ----------------

    async def _loop(self, user_id: str, interval: int) -> None:
        while not self._stop_event.is_set():
            # wait first: the bot must not trade on a cold cache, and callers
            # (tests, CLOSE ALL) get a window before the first cycle
            try:
                await asyncio.wait_for(self._stop_event.wait(), timeout=interval)
                break
            except TimeoutError:
                pass
            try:
                await self.tick(user_id)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # never let one bad cycle kill the bot
                log.exception("bot cycle failed")
                self.status.last_error = str(exc)
                with contextlib.suppress(Exception):
                    await self._log(user_id, "bot cycle error", level="error")
            self._cycle += 1

    async def tick(self, user_id: str) -> None:
        async with self.session_factory() as session:
            store = Store(session)
            settings_row = await store.settings(user_id)
            portfolio = await store.portfolio(user_id)
            self._absorb(portfolio, await store.trades_today(user_id))

            if self._close_all.is_set():
                self._close_all.clear()
                await self._execute_closes(store, user_id, ExitReason.CLOSE_ALL)
                await session.commit()
                return

            await self._manage_positions(store, user_id, settings_row, portfolio)

            if not self.is_running or self._stop_event.is_set():
                await session.commit()
                return

            portfolio = await self._scan_and_enter(store, user_id, settings_row, portfolio)

            if self.status.run_id and self._cycle % HEARTBEAT_EVERY_CYCLES == 0:
                await store.heartbeat(self.status.run_id)
            if self._cycle % SNAPSHOT_EVERY_CYCLES == 0:
                await store.snapshot(user_id, portfolio)
            self.status.open_positions = portfolio.open_positions
            await session.commit()

    def _absorb(self, portfolio: Portfolio, trades_today: int) -> None:
        self.status.equity_usd = portfolio.equity_usd
        self.status.today_pnl_usd = portfolio.today_pnl_usd
        self.status.win_rate = portfolio.win_rate
        self.status.open_positions = portfolio.open_positions
        self.status.today_trades = trades_today

    # ---------------- entry ----------------

    async def _scan_and_enter(self, store: Store, user_id: str, settings_row, portfolio: Portfolio):
        self.scanner.min_liquidity_usd = settings_row.min_liquidity_usd
        self.scanner.min_volume_5m_usd = settings_row.min_volume_5m_usd

        self.status.scanning = True
        try:
            candidates, scanned = await self.scanner.scan()
        finally:
            self.status.scanning = False

        self.status.tokens_scanned = scanned
        tradable = [c for c in candidates if c.total_score >= settings_row.min_entry_score]
        self.status.opportunities = len(tradable)

        cooling = await store.recently_closed_mints(user_id, settings_row.reentry_cooldown_minutes)

        for candidate in tradable:
            if self._stop_event.is_set() or not self.is_running:
                return portfolio
            if portfolio.open_positions >= settings_row.max_open_positions:
                return portfolio
            mint = candidate.snapshot.mint or ""
            if not mint:
                continue
            if mint in cooling:
                continue
            if await store.position_by_mint(user_id, mint):
                continue
            if await self._try_enter(store, user_id, settings_row, portfolio, candidate):
                portfolio = await store.portfolio(user_id)
        return portfolio

    async def _try_enter(
        self, store: Store, user_id: str, settings_row, portfolio: Portfolio, candidate: Candidate
    ) -> bool:
        snap = candidate.snapshot
        decision = evaluate_buy(
            candidate,
            equity_usd=portfolio.equity_usd,
            cash_usd=portfolio.cash_usd,
            open_positions=portfolio.open_positions,
            realized_pnl_today=portfolio.realized_today_usd,
            limits=limits_from_settings(settings_row),
        )
        if not decision.approved:
            if decision.halt and not self.status.halted:
                self.status.halted = True
                await store.log(
                    user_id,
                    f"RISK HALT: {', '.join(decision.reasons)} - no new entries today",
                    level="warning",
                    category="risk",
                )
            return False

        await store.upsert_token(snap, candidate.total_score, candidate.score.as_dict())

        try:
            fill = await self.executor.buy(self.wallet_address, snap, decision.usd_size)
        except NeedsClientSignature as exc:
            self._queue_signature(
                kind="buy",
                symbol=exc.symbol,
                mint=exc.mint,
                side=exc.side,
                unsigned_tx=exc.signed_tx,
                extra={"usd_size": decision.usd_size},
            )
            await store.log(
                user_id,
                f"{snap.symbol}: quote ready, waiting for wallet signature",
                category="execution",
                symbol=snap.symbol,
            )
            return False
        except ExecutionError as exc:
            await store.log(
                user_id,
                f"{snap.symbol}: buy failed - {exc}",
                level="error",
                category="execution",
                symbol=snap.symbol,
            )
            return False

        params = exit_params_from_settings(settings_row)
        position = await store.record_buy(
            user_id,
            self.status.run_id,
            fill,
            entry_score=candidate.total_score,
            reason=f"score_{candidate.total_score:.0f}",
            stop_loss=params.stop_for(fill.price),
            take_profit=params.target_for(fill.price),
            entry_liquidity_usd=snap.liquidity_usd,
        )
        await store.record_trade(
            user_id,
            fill,
            run_id=self.status.run_id,
            position_id=position.id,
            reason=f"entry_{candidate.total_score:.0f}",
            mode=self.mode,
        )
        await store.log(
            user_id,
            f"BUY {snap.symbol} ${fill.usd_amount:.2f} @ ${fill.price:.12g} "
            f"(score {candidate.total_score:.0f})",
            category="entry",
            symbol=snap.symbol,
            payload={"score": candidate.score.as_dict(), "route": fill.route_summary},
        )
        return True

    # ---------------- position management ----------------

    async def _manage_positions(
        self, store: Store, user_id: str, settings_row, portfolio: Portfolio
    ) -> None:
        positions = await store.open_positions(user_id)
        if not positions:
            return

        params = exit_params_from_settings(settings_row)
        prices = await self.scanner.refresh_prices([p.mint for p in positions])
        exit_queue: list[tuple] = []

        for position in positions:
            price = prices.get(position.mint) or position.current_price
            if not price or price <= 0:
                continue
            peak = max(position.peak_price or 0.0, price)
            trailing = params.trailing_for(position.entry_price, peak)
            await store.mark_position(position, price, trailing)

            snap = await self.scanner.pair_snapshot(position.pair_address)
            current_score = None
            if snap:
                current_score = (await self.scanner.score(snap)).total_score
            opened = position.opened_at
            hold_minutes = (utcnow() - opened).total_seconds() / 60 if opened else 0.0

            signal = evaluate_exit(
                entry_price=position.entry_price,
                current_price=price,
                peak_price=peak,
                stop_loss=position.stop_loss or params.stop_for(position.entry_price),
                take_profit=position.take_profit or params.target_for(position.entry_price),
                trailing_stop=trailing,
                entry_score=position.score_at_entry,
                current_score=current_score,
                current_liquidity_usd=snap.liquidity_usd if snap else None,
                entry_liquidity_usd=position.entry_liquidity_usd,
                hold_minutes=hold_minutes,
                whale_dump=bool(snap and snap.price_change_5m < -35 and snap.buy_sell_ratio < 0.6),
                params=params,
            )
            if signal:
                exit_queue.append((position, signal))

        for position, signal in exit_queue:
            await self._close(store, user_id, position, signal.reason, signal.detail)

    async def _execute_closes(self, store: Store, user_id: str, reason: ExitReason) -> None:
        for position in await store.open_positions(user_id):
            await self._close(store, user_id, position, reason, "close all requested")

    async def _close(
        self, store: Store, user_id: str, position, reason: ExitReason | str, detail: str = ""
    ) -> bool:
        try:
            fill = await self.executor.sell(self.wallet_address, position)
        except NeedsClientSignature as exc:
            self._queue_signature(
                kind="sell",
                symbol=exc.symbol,
                mint=exc.mint,
                side=exc.side,
                unsigned_tx=exc.signed_tx,
                extra={"position_id": position.id},
            )
            await store.log(
                user_id,
                f"{position.symbol}: exit quote ready ({reason}), waiting for wallet signature",
                category="execution",
                symbol=position.symbol,
            )
            return False
        except ExecutionError as exc:
            await store.log(
                user_id,
                f"{position.symbol}: sell failed - {exc}",
                level="error",
                category="exit",
                symbol=position.symbol,
            )
            return False

        pnl = await store.close_position(position, fill, reason)
        await store.record_trade(
            user_id,
            fill,
            run_id=self.status.run_id,
            position_id=position.id,
            reason=str(reason),
            pnl_usd=pnl,
            mode=self.mode,
        )
        await store.log(
            user_id,
            (
                f"SELL {position.symbol} @ ${fill.price:.12g} -> {pnl:+.2f} ({reason}) {detail}"
            ).strip(),
            category="exit",
            symbol=position.symbol,
            payload={"reason": str(reason), "pnl_usd": pnl, "tx": fill.tx_signature},
        )
        return True

    # ---------------- helpers ----------------

    def _queue_signature(self, **payload) -> None:
        payload["queued_at"] = utcnow().isoformat()
        self.status.pending_txs.append(payload)

    async def _log(self, user_id: str, message: str, *, level: str = "info") -> None:
        async with self.session_factory() as session:
            await Store(session).log(user_id, message, level=level)
            await session.commit()
