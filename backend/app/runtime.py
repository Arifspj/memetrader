"""Process-wide singletons: API clients, executor, and per-user bot instances."""

from __future__ import annotations

import asyncio

from app.clients.dexscreener import DexScreenerClient
from app.clients.gemini import GeminiClient
from app.clients.helius import HeliusClient
from app.clients.jupiter import JupiterClient
from app.config import settings
from app.db import SessionLocal
from app.engine.bot import TradingBot
from app.engine.scanner import Scanner
from app.execution import build_executor


class Runtime:
    def __init__(self) -> None:
        self.dex = DexScreenerClient()
        self.helius = HeliusClient()
        self.jupiter = JupiterClient()
        self.gemini = GeminiClient()
        self.executor = build_executor(settings, self.jupiter)
        self._bots: dict[str, TradingBot] = {}
        self._lock = asyncio.Lock()

    def bot_for(self, user_id: str) -> TradingBot:
        bot = self._bots.get(user_id)
        if bot is None:
            scanner = Scanner(self.dex, self.helius)
            bot = TradingBot(
                session_factory=SessionLocal,
                scanner=scanner,
                executor=self.executor,
                mode=settings.execution_mode,
            )
            self._bots[user_id] = bot
        return bot

    async def aclose(self) -> None:
        for bot in self._bots.values():
            await bot.shutdown()
        await self.dex.aclose()
        await self.helius.aclose()
        await self.jupiter.aclose()
        await self.gemini.aclose()


runtime = Runtime()
