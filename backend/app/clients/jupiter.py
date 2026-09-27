"""Jupiter v6 quote + swap builder.

The backend never holds a private key. For real (non-paper) execution the flow is:

    bot decision -> quote() -> build_swap_transaction() -> base64 tx
                -> app signs with Phantom (session/embedded wallet)
                -> app POSTs signed tx to /tx/submit
                -> backend confirms and records the fill
"""

from __future__ import annotations

import base64
from typing import Any

import httpx

from app.config import settings
from app.engine.types import FillResult, Side

WSOL_MINT = "So11111111111111111111111111111111111111112"
USDC_MINT = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

SOL_DECIMALS = 9
USDC_DECIMALS = 6


class JupiterError(RuntimeError):
    pass


def to_base_units(amount: float, decimals: int) -> int:
    return int(round(amount * (10**decimals)))


def route_summary(quote: dict[str, Any]) -> str:
    route = quote.get("routePlan") or []
    return " -> ".join(leg.get("swapInfo", {}).get("label", "?") for leg in route)


class JupiterClient:
    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client
        self._owns_client = client is None

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            headers = {"User-Agent": settings.user_agent, "Accept": "application/json"}
            if settings.jupiter_api_key:
                headers["x-api-key"] = settings.jupiter_api_key
            self._client = httpx.AsyncClient(
                base_url=settings.jupiter_base_url,
                timeout=settings.http_timeout_seconds,
                headers=headers,
            )
            self._owns_client = True
        return self._client

    async def aclose(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    async def _req(self, method: str, path: str, **kw: Any) -> dict[str, Any]:
        try:
            resp = await self._http().request(method, path, **kw)
        except httpx.HTTPError as exc:
            raise JupiterError(str(exc)) from exc
        if resp.status_code >= 400:
            raise JupiterError(f"{path} -> {resp.status_code}: {resp.text[:300]}")
        return resp.json()

    async def quote(
        self,
        input_mint: str,
        output_mint: str,
        amount_base_units: int,
        slippage_bps: int = 100,
    ) -> dict[str, Any] | None:
        data = await self._req(
            "GET",
            "/quote",
            params={
                "inputMint": input_mint,
                "outputMint": output_mint,
                "amount": amount_base_units,
                "slippageBps": slippage_bps,
                "restrictIntermediateTokens": "true",
            },
        )
        return data or None

    async def quote_usd(self, usd_amount: float, output_mint: str) -> dict[str, Any] | None:
        return await self.quote(
            USDC_MINT, output_mint, to_base_units(usd_amount, USDC_DECIMALS), slippage_bps=150
        )

    async def quote_sell(self, qty: float, input_mint: str) -> dict[str, Any] | None:
        decimals = SOL_DECIMALS if input_mint == WSOL_MINT else _guess_decimals(input_mint)
        return await self.quote(
            input_mint, USDC_MINT, to_base_units(qty, decimals), slippage_bps=200
        )

    async def build_swap_transaction(self, quote: dict[str, Any], user_public_key: str) -> str:
        """Returns a base64 Solana transaction the client must sign."""
        if "error" in quote:
            raise JupiterError(str(quote["error"]))
        try:
            data = await self._req(
                "GET",
                "/swap",
                params={"quoteResponse": quote, "userPublicKey": user_public_key},
            )
        except JupiterError:
            # older v6 deployments only expose POST /swap
            data = await self._req(
                "POST",
                "/swap",
                json={"quoteResponse": quote, "userPublicKey": user_public_key},
            )
        tx = data.get("swapTransaction") or data.get("transaction")
        if not tx:
            raise JupiterError(f"no transaction in swap response: {str(data)[:200]}")
        return str(tx)

    async def submit_signed(self, signed_tx_base64: str) -> str:
        data = await self._req(
            "POST",
            "/tx/submit",
            json={"serializedTransaction": base64.b64decode(signed_tx_base64).hex()},
        )
        return str(data.get("signature") or data.get("txid") or "")

    # ---------- helpers ----------

    async def buy_quote(
        self, symbol: str, mint: str, usd_amount: float
    ) -> tuple[dict, float, float]:
        quote = await self.quote_usd(usd_amount, mint)
        if not quote:
            raise JupiterError(f"no quote for {symbol} ({mint})")
        out_amount = int(quote["outAmount"])
        qty = out_amount / (10 ** _guess_decimals(mint))
        price = usd_amount / qty if qty else 0.0
        return quote, qty, price

    async def sell_quote(self, symbol: str, mint: str, qty: float) -> tuple[dict, float, float]:
        quote = await self.quote_sell(qty, mint)
        if not quote:
            raise JupiterError(f"no quote for {symbol} ({mint})")
        in_amount = int(quote["inAmount"])
        usd_out = int(quote["outAmount"]) / (10**USDC_DECIMALS)
        price = usd_out / (in_amount / (10 ** _guess_decimals(mint))) if in_amount else 0.0
        return quote, usd_out, price


def _guess_decimals(mint: str) -> int:
    from app.clients.helius import token_decimals

    return token_decimals(mint)


def fill_from_quote(
    side: Side,
    symbol: str,
    mint: str,
    pair_address: str,
    dex_id: str,
    quote: dict[str, Any],
    usd_amount: float,
    qty: float,
    price: float,
    tx_signature: str | None = None,
    pending_signature: str | None = None,
) -> FillResult:
    impact = float(quote.get("priceImpactPct") or 0.0) * 10_000
    return FillResult(
        side=side,
        symbol=symbol,
        mint=mint,
        pair_address=pair_address,
        dex_id=dex_id,
        usd_amount=usd_amount,
        qty=qty,
        price=price,
        tx_signature=tx_signature,
        pending_signature=pending_signature,
        price_impact_bps=impact,
        route_summary=route_summary(quote),
    )
