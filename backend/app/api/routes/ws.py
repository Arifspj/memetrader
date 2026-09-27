"""WebSocket: live bot + portfolio feed for the Home / AI / Logs screens."""

from __future__ import annotations

import asyncio
import contextlib
import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.core.security import decode_access_token
from app.db import SessionLocal
from app.runtime import runtime
from app.service.store import Store

router = APIRouter(tags=["stream"])
STREAM_INTERVAL_SECONDS = 3


@router.websocket("/ws/stream")
async def stream(websocket: WebSocket, token: str = "") -> None:
    payload = decode_access_token(token)
    if not payload or not payload.get("sub"):
        await websocket.close(code=4401)
        return

    await websocket.accept()
    user_id = payload["sub"]
    bot = runtime.bot_for(user_id)

    try:
        while True:
            async with SessionLocal() as session:
                store = Store(session)
                portfolio = await store.portfolio(user_id)
                events = await store.events(user_id, limit=20)
                await session.commit()
            message = {
                "type": "state",
                "state": bot.status.state.value,
                "mode": bot.mode,
                "scanning": bot.status.scanning,
                "tokens_scanned": bot.status.tokens_scanned,
                "opportunities": bot.status.opportunities,
                "open_positions": portfolio.open_positions,
                "equity_usd": portfolio.equity_usd,
                "today_pnl_usd": portfolio.today_pnl_usd,
                "win_rate": portfolio.win_rate,
                "pending_txs": len(bot.status.pending_txs),
                "latest": [
                    {
                        "id": e.id,
                        "level": e.level,
                        "category": e.category,
                        "symbol": e.symbol,
                        "message": e.message,
                        "created_at": e.created_at.isoformat() if e.created_at else None,
                    }
                    for e in events[-5:]
                ],
            }
            await websocket.send_text(json.dumps(message, default=str))
            await asyncio.sleep(STREAM_INTERVAL_SECONDS)
    except (WebSocketDisconnect, RuntimeError):
        return
    except Exception:
        with contextlib.suppress(Exception):
            await websocket.close(code=1011)
        return
