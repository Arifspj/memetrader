from fastapi import APIRouter, HTTPException

from app.core.security import (
    build_message,
    consume_nonce,
    create_access_token,
    issue_nonce,
    verify_wallet_signature,
)
from app.deps import SessionDep
from app.schemas import LoginRequest
from app.service.store import Store

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/nonce")
async def nonce(wallet_address: str) -> dict:
    """Step 1: server hands out a nonce and the exact message to sign."""
    value, message = issue_nonce(wallet_address)
    return {"nonce": value, "message": message}


@router.post("/login")
async def login(payload: LoginRequest, session: SessionDep) -> dict:
    """Step 2: verify the wallet signature, return a JWT."""
    store = Store(session)
    user = await store.get_or_create_user(payload.wallet_address)

    parts = [line for line in payload.message.splitlines() if line.startswith("Nonce:")]
    server_message = None
    if parts:
        expected = build_message(payload.wallet_address, parts[0].split(":", 1)[1].strip())
        server_message = expected if expected == payload.message else None

    if server_message is None or not verify_wallet_signature(
        payload.wallet_address, payload.message, payload.signature
    ):
        raise HTTPException(401, "signature verification failed")
    nonce_value = parts[0].split(":", 1)[1].strip()
    if consume_nonce(nonce_value) != payload.wallet_address:
        raise HTTPException(401, "nonce invalid or expired")

    await session.commit()
    return {
        "access_token": create_access_token(user.id, user.wallet_address),
        "token_type": "bearer",
        "wallet_address": user.wallet_address,
        "user_id": user.id,
    }
