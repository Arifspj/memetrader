"""DexScreener REST client (no API key required).

Rate limits: /latest/dex/* ~300 req/min, /token-pairs/v1/* ~60 req/min.
We keep one client per process and a tiny response cache to stay well under.

All paths below are absolute against the API root, because DexScreener is not
consistent: market data lives under /latest/dex but token-boosts, token-profiles
and token-pairs sit at the root.
"""

from __future__ import annotations

import asyncio
import time
from datetime import UTC, datetime
from typing import Any

import httpx

from app.config import settings
from app.engine.types import TokenSnapshot

SOLANA = "solana"


class DexScreenerError(RuntimeError):
    pass


def _f(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _i(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _iso(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_pair(pair: dict[str, Any]) -> TokenSnapshot | None:
    base = pair.get("baseToken") or {}
    liquidity = pair.get("liquidity") or {}
    volume = pair.get("volume") or {}
    change = pair.get("priceChange") or {}
    txns = ((pair.get("txns") or {}).get("m5")) or {}
    chain = (pair.get("chainId") or "").lower()
    if chain != SOLANA:
        return None
    mint = base.get("address")
    pair_address = pair.get("pairAddress")
    symbol = base.get("symbol") or "???"
    if not mint or not pair_address or not symbol:
        return None

    return TokenSnapshot(
        chain=chain,
        pair_address=pair_address,
        dex_id=pair.get("dexId") or "unknown",
        symbol=symbol,
        name=base.get("name") or None,
        mint=mint,
        image_url=pair.get("info", {}).get("imageUrl") or base.get("imageUrl"),
        price_usd=_f(pair.get("priceUsd")),
        liquidity_usd=_f(liquidity.get("usd")),
        volume_5m=_f(volume.get("m5")),
        volume_24h=_f(volume.get("h24")),
        price_change_5m=_f(change.get("m5")),
        price_change_1h=_f(change.get("h1")),
        price_change_24h=_f(change.get("h24")),
        txns_5m_buys=_i(txns.get("buys")),
        txns_5m_sells=_i(txns.get("sells")),
        pair_created_at=_iso(pair.get("pairCreatedAt")),
    )


class DexScreenerClient:
    def __init__(self, client: httpx.AsyncClient | None = None, ttl: float | None = None) -> None:
        self._client = client
        self._owns_client = client is None
        self._ttl = settings.dexscreener_cache_ttl if ttl is None else ttl
        self._cache: dict[str, tuple[float, Any]] = {}
        self._locks: dict[str, asyncio.Lock] = {}
        self._sem = asyncio.Semaphore(8)

    async def __aenter__(self) -> DexScreenerClient:
        return self

    async def __aexit__(self, *exc: object) -> None:
        await self.aclose()

    async def aclose(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                base_url=settings.dexscreener_root_url,
                timeout=settings.http_timeout_seconds,
                headers={"User-Agent": settings.user_agent, "Accept": "application/json"},
            )
            self._owns_client = True
        return self._client

    async def _get(self, path: str, params: dict | None = None) -> Any:
        key = f"{path}?{sorted((params or {}).items())}"
        now = time.monotonic()
        cached = self._cache.get(key)
        if cached and now - cached[0] < self._ttl:
            return cached[1]

        lock = self._locks.setdefault(key, asyncio.Lock())
        async with lock:
            cached = self._cache.get(key)
            if cached and time.monotonic() - cached[0] < self._ttl:
                return cached[1]
            async with self._sem:
                try:
                    resp = await self._http().get(path, params=params)
                    resp.raise_for_status()
                    data = resp.json()
                except (httpx.HTTPError, ValueError) as exc:
                    raise DexScreenerError(f"{path}: {exc}") from exc
            self._cache[key] = (time.monotonic(), data)
            return data

    # ---------- discovery ----------

    async def boosted_tokens(self, kind: str = "latest") -> list[str]:
        """Freshly promoted solana tokens - the best free 'new pairs' feed.

        NOTE: these endpoints live at the API root, not under /latest/dex.
        """
        data = await self._get(f"/token-boosts/{kind}/v1")
        out: list[str] = []
        for row in data or []:
            if (row.get("chainId") or "").lower() == SOLANA:
                addr = row.get("tokenAddress")
                if addr:
                    out.append(addr)
        return out

    async def latest_profiles(self) -> list[str]:
        """Newly published token profiles - a second free discovery feed."""
        data = await self._get("/token-profiles/latest/v1")
        return [
            row["tokenAddress"]
            for row in (data or [])
            if (row.get("chainId") or "").lower() == SOLANA and row.get("tokenAddress")
        ]

    async def search(self, query: str) -> list[TokenSnapshot]:
        data = await self._get("/latest/dex/search", {"q": query})
        pairs = (data or {}).get("pairs") or []
        return [s for s in (parse_pair(p) for p in pairs) if s]

    async def token_pairs(self, token_address: str) -> list[TokenSnapshot]:
        data = await self._get(f"/token-pairs/v1/{SOLANA}/{token_address}")
        if isinstance(data, dict):
            data = [data]
        return [s for s in (parse_pair(p) for p in (data or [])) if s]

    async def tokens(self, addresses: list[str]) -> list[TokenSnapshot]:
        """Batch: up to 30 comma separated token addresses."""
        out: list[TokenSnapshot] = []
        for chunk in _chunks([a for a in addresses if a], 30):
            data = await self._get("/latest/dex/tokens/" + ",".join(chunk))
            pairs = (data or {}).get("pairs") or []
            out.extend(s for s in (parse_pair(p) for p in pairs) if s)
        return out

    async def pair(self, pair_address: str) -> TokenSnapshot | None:
        data = await self._get(f"/latest/dex/pairs/{SOLANA}/{pair_address}")
        pairs = (data or {}).get("pairs") or []
        for p in pairs:
            snap = parse_pair(p)
            if snap:
                return snap
        return None

    async def prices(self, mints: list[str]) -> dict[str, float]:
        snaps = await self.tokens(mints)
        return {s.mint: s.price_usd for s in snaps if s.mint and s.price_usd > 0}


def _chunks(items: list[str], size: int) -> list[list[str]]:
    return [items[i : i + size] for i in range(0, len(items), size)]


def as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value if value.tzinfo else value.replace(tzinfo=UTC)
