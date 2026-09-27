"""Execution layer interface.

An executor turns an engine decision into a FillResult. Two implementations ship:

  PaperExecutor  - no keys, no wallet, deterministic fills (default)
  JupiterExecutor- real Jupiter quotes + unsigned transaction handed back to the
                   app, which signs with the Phantom Connect embedded wallet.
"""

from __future__ import annotations

from typing import Protocol

from app.engine.types import FillResult, TokenSnapshot


class ExecutionError(RuntimeError):
    pass


class NeedsClientSignature(Exception):
    """Raised when the trade cannot complete without a wallet signature.

    `signed_tx` (base64) is attached so the API can hand it to the app.
    """

    def __init__(self, signed_tx: str, mint: str, symbol: str, side: str) -> None:
        super().__init__(f"client signature required for {side} {symbol}")
        self.signed_tx = signed_tx
        self.mint = mint
        self.symbol = symbol
        self.side = side


class Executor(Protocol):
    mode: str

    async def buy(
        self, wallet_address: str, snap: TokenSnapshot, usd_size: float
    ) -> FillResult: ...

    async def sell(self, wallet_address: str, position) -> FillResult: ...

    async def aclose(self) -> None: ...
