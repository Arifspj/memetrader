"""Jupiter executor for the real (non-paper) flow.

Signing never happens here. For every swap the backend:

  1. gets a Jupiter quote
  2. asks Jupiter to assemble the transaction for the user's public key
  3. raises NeedsClientSignature(signed_tx) -> the API returns the unsigned tx

The Flutter app signs it with the Phantom Connect embedded wallet (session key)
and POSTs the signed transaction back to /wallet/tx/submit. The bot then records
the fill. This keeps the private key off our servers while still allowing
unattended START -> trade -> STOP operation once a session key is authorised.
"""

from __future__ import annotations

import logging

from app.clients.jupiter import JupiterClient, fill_from_quote
from app.engine.types import ExitReason, FillResult, Side, TokenSnapshot
from app.execution.base import ExecutionError, NeedsClientSignature

log = logging.getLogger(__name__)

USDC_MINT = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"


class JupiterExecutor:
    mode = "jupiter"

    def __init__(self, jupiter: JupiterClient) -> None:
        self.jupiter = jupiter

    async def buy(self, wallet_address: str, snap: TokenSnapshot, usd_size: float) -> FillResult:
        if not snap.mint:
            raise ExecutionError(f"no mint for {snap.symbol}")
        try:
            quote, qty, price = await self.jupiter.buy_quote(snap.symbol, snap.mint, usd_size)
        except Exception as exc:
            raise ExecutionError(f"buy quote failed for {snap.symbol}: {exc}") from exc
        if qty <= 0:
            raise ExecutionError(f"buy quote returned zero qty for {snap.symbol}")
        tx = await self.jupiter.build_swap_transaction(quote, wallet_address)
        raise NeedsClientSignature(tx, snap.mint, snap.symbol, Side.BUY.value)

    async def sell(self, wallet_address: str, position) -> FillResult:
        try:
            quote, usd_out, price = await self.jupiter.sell_quote(
                position.symbol, position.mint, position.qty
            )
        except Exception as exc:
            raise ExecutionError(f"sell quote failed for {position.symbol}: {exc}") from exc
        tx = await self.jupiter.build_swap_transaction(quote, wallet_address)
        raise NeedsClientSignature(tx, position.mint, position.symbol, Side.SELL.value)

    def preview_buy(self, snap: TokenSnapshot, usd_size: float) -> FillResult:
        """Quote-only view used by the Trade screen (no tx, no signature)."""
        import asyncio

        async def _go() -> FillResult:
            if not snap.mint:
                raise ExecutionError(f"no mint for {snap.symbol}")
            quote, qty, price = await self.jupiter.buy_quote(snap.symbol, snap.mint, usd_size)
            return fill_from_quote(
                Side.BUY,
                snap.symbol,
                snap.mint,
                snap.pair_address,
                snap.dex_id,
                quote,
                usd_size,
                qty,
                price,
            )

        return asyncio.get_event_loop().run_until_complete(_go())  # pragma: no cover

    async def aclose(self) -> None:
        await self.jupiter.aclose()


__all__ = ["JupiterExecutor", "ExitReason", "USDC_MINT"]
