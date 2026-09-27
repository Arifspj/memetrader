from datetime import UTC, datetime, timedelta

from app.engine.types import TokenSnapshot


def make_snapshot(**overrides) -> TokenSnapshot:
    base = {
        "chain": "solana",
        "pair_address": "PAIR1",
        "dex_id": "raydium",
        "symbol": "MEME",
        "name": "Meme Coin",
        "mint": "MINT1",
        "price_usd": 0.0000124,
        "liquidity_usd": 850_000,
        "volume_5m": 320_000,
        "volume_24h": 4_000_000,
        "price_change_5m": 18.0,
        "price_change_1h": 45.0,
        "price_change_24h": 120.0,
        "txns_5m_buys": 184,
        "txns_5m_sells": 100,
        "pair_created_at": datetime.now(UTC) - timedelta(hours=6),
    }
    base.update(overrides)
    return TokenSnapshot(**base)
