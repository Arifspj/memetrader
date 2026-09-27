"""Scanner: turn raw DexScreener output into scored, de-risked candidates."""

from __future__ import annotations

import asyncio
import logging

from app.clients.dexscreener import DexScreenerClient
from app.clients.helius import HeliusClient
from app.engine.filters import run_safety_filters
from app.engine.scoring import score_token
from app.engine.types import Candidate, TokenSnapshot

log = logging.getLogger(__name__)

MIN_SCANNED_USD = 0.0
# how many boosted tokens we pull each cycle (keeps us inside rate limits)
DISCOVERY_BATCH = 60
MAX_DEXSCREENER_WORKERS = 4


class Scanner:
    def __init__(
        self,
        dexscreener: DexScreenerClient,
        helius: HeliusClient | None = None,
        *,
        min_liquidity_usd: float = 50_000.0,
        min_volume_5m_usd: float = 20_000.0,
        min_score: float = 0.0,
        with_holder_stats: bool = False,
    ) -> None:
        self.dex = dexscreener
        self.helius = helius
        self.min_liquidity_usd = min_liquidity_usd
        self.min_volume_5m_usd = min_volume_5m_usd
        self.min_score = min_score
        self.with_holder_stats = with_holder_stats
        self._prev_volume: dict[str, float] = {}

    async def discover(self) -> list[str]:
        """Fresh solana token addresses from the free DexScreener feeds."""
        feeds = await asyncio.gather(
            self.dex.boosted_tokens("latest"),
            self.dex.boosted_tokens("top"),
            self.dex.latest_profiles(),
            return_exceptions=True,
        )
        seen: dict[str, None] = {}
        for feed in feeds:
            if isinstance(feed, BaseException):
                log.warning("discovery feed failed: %s", feed)
                continue
            for addr in feed:
                seen.setdefault(addr, None)
        return list(seen)[:DISCOVERY_BATCH]

    async def fetch_snapshots(self, addresses: list[str]) -> list[TokenSnapshot]:
        try:
            return await self.dex.tokens(addresses)
        except Exception:
            log.exception("dexscreener tokens fetch failed")
            return []

    async def score(self, snap: TokenSnapshot) -> Candidate:
        holder_stats = None
        if self.with_holder_stats and self.helius and snap.mint:
            try:
                holder_stats = await self.helius.holder_stats(snap.mint)
            except Exception:
                log.debug("holder_stats failed for %s", snap.mint, exc_info=True)

        safety = run_safety_filters(
            snap,
            min_liquidity_usd=self.min_liquidity_usd,
            min_volume_5m_usd=self.min_volume_5m_usd,
            holder_stats=holder_stats,
        )
        breakdown = score_token(
            snap,
            safety,
            prev_volume_5m=self._prev_volume.get(snap.pair_address),
            holder_stats=holder_stats,
        )
        self._prev_volume[snap.pair_address] = snap.volume_5m

        blocked: list[str] = []
        if not safety.passed:
            blocked.extend(safety.flags)

        return Candidate(snapshot=snap, safety=safety, score=breakdown, blocked_reasons=blocked)

    async def scan(self) -> tuple[list[Candidate], int]:
        """Returns (candidates sorted by score desc, tokens_seen)."""
        addresses = await self.discover()
        if not addresses:
            return [], 0

        snapshots = await self.fetch_snapshots(addresses)
        if not snapshots:
            return [], len(addresses)

        results = await asyncio.gather(*(self.score(s) for s in snapshots), return_exceptions=True)
        candidates = [c for c in results if isinstance(c, Candidate)]
        candidates.sort(key=lambda c: c.total_score, reverse=True)
        return candidates, len(addresses)

    async def refresh_prices(self, mints: list[str]) -> dict[str, float]:
        if not mints:
            return {}
        try:
            return await self.dex.prices(mints)
        except Exception:
            log.exception("price refresh failed")
            return {}

    async def pair_snapshot(self, pair_address: str) -> TokenSnapshot | None:
        try:
            return await self.dex.pair(pair_address)
        except Exception:
            log.exception("pair refresh failed for %s", pair_address)
            return None
