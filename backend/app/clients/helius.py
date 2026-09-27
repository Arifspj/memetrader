"""Solana RPC (Helius) client: balances, token accounts, DAS asset search.

Helius also exposes an RPC method ``getTokenAccountsByOwner`` via the standard
node plus ``searchAssets`` / ``getAssetsByOwner`` on the DAS API, which is what
we use for holder counts and whale activity.
"""

from __future__ import annotations

import asyncio
from typing import Any

import httpx

from app.clients.jupiter import USDC_MINT, WSOL_MINT
from app.config import settings

LAMPORTS_PER_SOL = 1_000_000_000

# Populated by the scanner / bot so jupiter can size quotes without extra RPC.
_TOKEN_DECIMALS: dict[str, int] = {}
_DEFAULT_DECIMALS = 6


def token_decimals(mint: str) -> int:
    return _TOKEN_DECIMALS.get(mint, _DEFAULT_DECIMALS)


def remember_token_decimals(mint: str, decimals: int) -> None:
    if mint and 0 <= decimals <= 9:
        _TOKEN_DECIMALS[mint] = decimals


class SolanaError(RuntimeError):
    pass


class HeliusClient:
    def __init__(self, client: httpx.AsyncClient | None = None, rpc_url: str | None = None) -> None:
        self._client = client
        self._owns_client = client is None
        self._rpc_url = rpc_url or settings.rpc_url

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=settings.http_timeout_seconds,
                headers={"User-Agent": settings.user_agent, "Content-Type": "application/json"},
            )
            self._owns_client = True
        return self._client

    async def aclose(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    async def rpc(self, method: str, params: list[Any] | None = None) -> dict[str, Any]:
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params or [],
        }
        try:
            resp = await self._http().post(self._rpc_url, json=payload)
            resp.raise_for_status()
            body = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise SolanaError(f"{method}: {exc}") from exc
        if "error" in body:
            raise SolanaError(f"{method}: {body['error']}")
        return body.get("result") or {}

    async def get_sol_balance(self, owner: str) -> float:
        res = await self.rpc("getBalance", [owner])
        return int(res.get("value") or 0) / LAMPORTS_PER_SOL

    async def get_spl_balance(self, owner: str, mint: str) -> float:
        res = await self.rpc(
            "getTokenAccountsByOwner",
            [
                owner,
                {"mint": mint},
                {"encoding": "jsonParsed"},
            ],
        )
        total = 0.0
        for acc in res.get("value") or []:
            info = acc.get("account", {}).get("data", {}).get("parsed", {}).get("info", {})
            amount = info.get("tokenAmount") or {}
            decimals = int(amount.get("decimals") or _DEFAULT_DECIMALS)
            remember_token_decimals(mint, decimals)
            total += float(amount.get("uiAmount") or 0.0)
        return total

    async def wallet_balances(self, owner: str) -> tuple[float, float]:
        sol, usdc = await asyncio.gather(
            self.get_sol_balance(owner),
            self.get_spl_balance(owner, USDC_MINT),
        )
        return sol, usdc

    async def get_price(self, base: str, quote: str) -> float | None:
        res = await self.rpc("getPrice", [base, quote])
        value = (res.get("value") or {}).get("price")
        return float(value) if value else None

    # ---------- DAS / enhanced ----------

    async def search_assets(self, **params: Any) -> dict[str, Any]:
        try:
            resp = await self._http().post(
                self._rpc_url,
                json={"jsonrpc": "2.0", "id": 1, "method": "searchAssets", "params": [params]},
            )
            body = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise SolanaError(f"searchAssets: {exc}") from exc
        return body.get("result") or {}

    async def holder_stats(self, mint: str) -> dict[str, Any]:
        """Rough holder/whale picture used by the scoring engine."""
        result = await self.search_assets(
            tokenMint=mint,
            tokenType="fungible",
            limit=1000,
            displayOptions={"showNativeBalance": True},
        )
        items = result.get("items") or []
        top10 = sorted((i.get("token_info", {}) or {}).get("balance", 0) for i in items)[-10:]
        total_supply = result.get("total", 0) or 0
        top10_pct = (sum(top10) / total_supply * 100) if total_supply else 0.0
        return {
            "holders": len(items),
            "top10_pct": top10_pct,
            "concentrated": top10_pct > 40,
        }

    async def confirm_tx(self, signature: str, search_transaction_history: bool = False) -> bool:
        try:
            res = await self.rpc(
                "getSignatureStatuses",
                [[signature], {"searchTransactionHistory": search_transaction_history}],
            )
        except SolanaError:
            return False
        values = res.get("value") or []
        first = values[0] if values else None
        return bool(first and first.get("err") is None and first.get("confirmationStatus"))


def wrapped_sol(mint: str) -> bool:
    return mint == WSOL_MINT
