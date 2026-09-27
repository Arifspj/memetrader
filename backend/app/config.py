"""Application settings, loaded from environment / .env file."""

from functools import lru_cache
from typing import Literal

from pydantic import Field, computed_field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: Literal["dev", "prod"] = "dev"
    secret_key: str = "change-me"
    api_base_url: str = "http://localhost:8000"

    database_url: str = "sqlite+aiosqlite:///./memetrader.db"
    redis_url: str = "redis://localhost:6379/0"

    solana_rpc_url: str = "https://api.devnet.solana.com"
    helius_api_key: str = ""

    dexscreener_base_url: str = "https://api.dexscreener.com/latest/dex"
    # token-boosts / token-profiles live at the root, not under /latest/dex
    dexscreener_root_url: str = "https://api.dexscreener.com"

    execution_mode: Literal["paper", "jupiter"] = "paper"
    jupiter_base_url: str = "https://quote-api.jup.ag/v6"
    jupiter_api_key: str = ""

    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.0-flash"

    starting_capital_usd: float = 1000.0
    risk_per_trade_pct: float = 1.0
    max_open_positions: int = 5
    max_daily_loss_pct: float = 5.0
    take_profit_pct: float = 12.0
    stop_loss_pct: float = 6.0
    trailing_activation_pct: float = 8.0
    trailing_drop_pct: float = 4.0
    max_hold_minutes: int = 240
    scan_interval_seconds: int = Field(default=20, ge=5)
    min_entry_score: float = 80.0
    reentry_cooldown_minutes: int = 15

    http_timeout_seconds: float = 12.0
    dexscreener_cache_ttl: float = 10.0
    user_agent: str = "memetrader/0.1"

    @computed_field  # type: ignore[prop-decorator]
    @property
    def is_paper(self) -> bool:
        return self.execution_mode == "paper"

    @property
    def rpc_url(self) -> str:
        if self.helius_api_key:
            return f"https://mainnet.helius-rpc.com/?api-key={self.helius_api_key}"
        return self.solana_rpc_url

    @property
    def jupiter_slugs(self) -> str:
        return "api.jup.ag"


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
