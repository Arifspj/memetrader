from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.config import settings
from app.deps import CurrentUser, SessionDep
from app.runtime import runtime
from app.schemas import WalletOut
from app.service.store import Store

router = APIRouter(prefix="/wallet", tags=["wallet"])


@router.get("", response_model=WalletOut)
async def wallet(user: CurrentUser, session: SessionDep) -> WalletOut:
    sol = usdc = None
    try:
        sol, usdc = await runtime.helius.wallet_balances(user.wallet_address)
    except Exception:
        pass
    bot = runtime.bot_for(user.id)
    return WalletOut(
        wallet_address=user.wallet_address,
        balance_sol=sol,
        balance_usdc=usdc,
        has_session_key=bool(bot.status.pending_txs) or settings.execution_mode == "paper",
        execution_mode=settings.execution_mode,
    )


class SubmitTxRequest(BaseModel):
    signed_transaction: str
    symbol: str | None = None
    side: str | None = None
    position_id: str | None = None


@router.post("/tx/submit")
async def submit_tx(user: CurrentUser, session: SessionDep, payload: SubmitTxRequest) -> dict:
    """App signs a bot-prepared Jupiter tx with Phantom and posts it back here."""
    if settings.execution_mode != "jupiter":
        raise HTTPException(409, "backend is in paper mode, nothing to submit")

    try:
        signature = await runtime.jupiter.submit_signed(payload.signed_transaction)
    except Exception as exc:
        await Store(session).log(
            user.id,
            f"tx submit failed: {exc}",
            level="error",
            category="execution",
            symbol=payload.symbol,
        )
        await session.commit()
        raise HTTPException(502, f"jupiter rejected the transaction: {exc}") from exc

    confirmed = False
    if signature:
        try:
            confirmed = await runtime.helius.confirm_tx(signature)
        except Exception:
            confirmed = False

    bot = runtime.bot_for(user.id)
    bot.status.pending_txs = [
        item for item in bot.status.pending_txs if item.get("symbol") != payload.symbol
    ]
    await Store(session).log(
        user.id,
        f"{payload.side or 'tx'} {payload.symbol or ''} submitted: {signature or 'n/a'}"
        f"{' (confirmed)' if confirmed else ''}",
        category="execution",
        symbol=payload.symbol,
        payload={"signature": signature, "confirmed": confirmed},
    )
    await session.commit()
    return {"signature": signature, "confirmed": confirmed}
