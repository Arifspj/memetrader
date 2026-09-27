"""Auth: Phantom message signing + JWT access tokens.

Flow:
  1. app GET  /auth/nonce  -> server returns a random nonce + the exact message
  2. app signs the message with the embedded/Phantom wallet
  3. app POST /auth/login {wallet_address, message, signature}
  4. server verifies the ed25519 signature, then issues a JWT

No private key ever touches this server.
"""

from __future__ import annotations

import base64
import secrets
import time
from datetime import UTC, datetime, timedelta

import jwt

from app.config import settings

NONCE_TTL_SECONDS = 300
ACCESS_TOKEN_TTL_MINUTES = 60 * 24 * 7

_nonces: dict[str, tuple[float, str]] = {}


def issue_nonce(wallet_address: str) -> tuple[str, str]:
    nonce = secrets.token_urlsafe(24)
    message = build_message(wallet_address, nonce)
    _nonces[nonce] = (time.time() + NONCE_TTL_SECONDS, wallet_address)
    return nonce, message


def build_message(wallet_address: str, nonce: str) -> str:
    return (
        "AI Meme Trader wants you to sign in with your Solana wallet.\n"
        f"Wallet: {wallet_address}\n"
        f"Nonce: {nonce}\n"
        "This request will not trigger a blockchain transaction or cost any fees."
    )


def consume_nonce(nonce: str) -> str | None:
    record = _nonces.get(nonce)
    if not record:
        return None
    expires_at, wallet = record
    _nonces.pop(nonce, None)
    if expires_at < time.time():
        return None
    return wallet


def verify_wallet_signature(wallet_address: str, message: str, signature_b64: str) -> bool:
    """Verify an ed25519 signature produced by Phantom's signMessage."""
    try:
        from nacl.exceptions import BadSignatureError
        from nacl.signing import VerifyKey
    except ImportError:  # pragma: no cover
        return False

    try:
        public_key = _b58_decode(wallet_address)
        signature = base64.b64decode(signature_b64)
        VerifyKey(public_key).verify(message.encode(), signature)
        return True
    except (BadSignatureError, ValueError, TypeError):
        return False
    except Exception:
        return False


_B58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def _b58_decode(value: str) -> bytes:
    number = 0
    for char in value:
        number = number * 58 + _B58_ALPHABET.index(char)
    body = number.to_bytes((number.bit_length() + 7) // 8, "big")
    pad = len(value) - len(value.lstrip("1"))
    return b"\x00" * pad + body


def create_access_token(user_id: str, wallet_address: str) -> str:
    now = datetime.now(UTC)
    payload = {
        "sub": user_id,
        "wallet": wallet_address,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=ACCESS_TOKEN_TTL_MINUTES)).timestamp()),
    }
    return jwt.encode(payload, settings.secret_key, algorithm="HS256")


def decode_access_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, settings.secret_key, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None
