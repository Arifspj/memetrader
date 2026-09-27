"""Gemini - optional narrative/context layer only.

The bot's trade decisions come from the quant scoring + risk engine. Gemini is
used to enrich the Logs/Trade screens (what narrative is this token riding?)
and to explain anomalies. Every call is best-effort: failures degrade to None.
"""

from __future__ import annotations

import json

import httpx

from app.config import settings

GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"


class GeminiClient:
    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client
        self._owns_client = client is None
        self._sem = None

    def enabled(self) -> bool:
        return bool(settings.gemini_api_key)

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=settings.http_timeout_seconds,
                headers={"User-Agent": settings.user_agent, "Content-Type": "application/json"},
            )
            self._owns_client = True
        return self._client

    async def aclose(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    async def _generate(self, prompt: str) -> str | None:
        if not self.enabled():
            return None
        url = GEMINI_URL.format(model=settings.gemini_model)
        body = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.2, "maxOutputTokens": 200},
        }
        try:
            resp = await self._http().post(f"{url}?key={settings.gemini_api_key}", json=body)
            resp.raise_for_status()
            data = resp.json()
        except (httpx.HTTPError, ValueError):
            return None
        try:
            return data["candidates"][0]["content"]["parts"][0]["text"]
        except (KeyError, IndexError):
            return None

    async def classify_narrative(self, symbol: str, name: str | None) -> dict | None:
        text = await self._generate(
            "Classify this Solana memecoin into one narrative and give a short "
            'tagline. Reply ONLY as JSON: {"narrative": str, "tagline": str, '
            '"is_rug_risk": bool}.\n'
            f"symbol={symbol} name={name or ''}"
        )
        if not text:
            return None
        start, end = text.find("{"), text.rfind("}")
        if start == -1 or end == -1:
            return None
        try:
            return json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            return None

    async def explain(self, symbol: str, context: str) -> str | None:
        return await self._generate(
            f"Explain in one sentence why the AI bot acted on solana memecoin {symbol}. "
            f"Context: {context}"
        )
