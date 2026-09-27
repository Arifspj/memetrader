"""Paper executor - the default safety mode. No keys, no wallet, no chain risk.

Fills at the observed market price plus a configurable slippage/fee so the P&L
curve is not fake-flat.
"""

from __future__ import annotations

import hashlib
import uuid

from app.engine.types import FillResult, Side, TokenSnapshot

DEFAULT_SLIPPAGE_BPS = 40
DEFAULT_FEE_BPS = 25  # AMM pool fee


class PaperExecutor:
    mode = "paper"

    def __init__(
        self, slippage_bps: float = DEFAULT_SLIPPAGE_BPS, fee_bps: float = DEFAULT_FEE_BPS
    ) -> None:
        self.slippage_bps = slippage_bps
        self.fee_bps = fee_bps

    @staticmethod
    def _signature(prefix: str, pair_address: str) -> str:
        digest = hashlib.sha256(f"{prefix}{pair_address}{uuid.uuid4()}".encode()).hexdigest()
        return f"paper_{digest[:64]}"

    def _fill_price(self, side: Side, market_price: float) -> float:
        drift = self.slippage_bps / 10_000.0
        return market_price * (1 + drift) if side is Side.BUY else market_price * (1 - drift)

    async def buy(self, wallet_address: str, snap: TokenSnapshot, usd_size: float) -> FillResult:
        price = self._fill_price(Side.BUY, snap.price_usd)
        qty = usd_size / price if price else 0.0
        return FillResult(
            side=Side.BUY,
            symbol=snap.symbol,
            mint=snap.mint or "",
            pair_address=snap.pair_address,
            dex_id=snap.dex_id,
            usd_amount=usd_size,
            qty=qty,
            price=price,
            tx_signature=self._signature("b", snap.pair_address),
            price_impact_bps=self.slippage_bps,
            route_summary=f"paper:{snap.dex_id}",
            fees_usd=usd_size * self.fee_bps / 10_000.0,
        )

    async def sell(self, wallet_address: str, position) -> FillResult:
        snap = TokenSnapshot(
            chain="solana",
            pair_address=position.pair_address,
            dex_id=position.dex_id,
            symbol=position.symbol,
            mint=position.mint,
            price_usd=position.current_price or position.entry_price,
        )
        price = self._fill_price(Side.SELL, snap.price_usd)
        proceeds = position.qty * price
        return FillResult(
            side=Side.SELL,
            symbol=position.symbol,
            mint=position.mint,
            pair_address=position.pair_address,
            dex_id=position.dex_id,
            usd_amount=proceeds,
            qty=position.qty,
            price=price,
            tx_signature=self._signature("s", position.pair_address),
            price_impact_bps=self.slippage_bps,
            route_summary=f"paper:{position.dex_id}",
            fees_usd=proceeds * self.fee_bps / 10_000.0,
        )

    async def aclose(self) -> None:
        return None
