"""FastAPI entrypoint."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.config import settings
from app.db import init_models
from app.runtime import runtime

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("app")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_models()
    log.info("execution_mode=%s rpc=%s", settings.execution_mode, settings.rpc_url)
    try:
        yield
    finally:
        await runtime.aclose()


app = FastAPI(
    title="AI Meme Trader",
    version="0.1.0",
    description=(
        "Solana meme-coin AI trading backend. Paper mode is the default; "
        "Jupiter execution requires the app to sign each transaction with the "
        "Phantom Connect embedded wallet."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router)


@app.get("/health")
async def health() -> dict:
    return {
        "status": "ok",
        "mode": settings.execution_mode,
        "chain": "devnet" if "devnet" in settings.rpc_url else "mainnet-beta",
    }
