from fastapi import APIRouter

from app.api.routes import auth, bot, market, positions, wallet, ws

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(wallet.router)
api_router.include_router(bot.router)
api_router.include_router(market.router)
api_router.include_router(positions.router)
api_router.include_router(ws.router)

__all__ = ["api_router"]
