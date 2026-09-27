"""API smoke tests: real ed25519 wallet signature -> JWT -> all read endpoints."""

from __future__ import annotations

import base64

import pytest
from fastapi.testclient import TestClient
from nacl.signing import SigningKey

from app.main import app

B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def b58encode(raw: bytes) -> str:
    number = int.from_bytes(raw, "big")
    out = ""
    while number:
        number, rem = divmod(number, 58)
        out = B58[rem] + out
    return (
        out * (1 + len(raw) - len(raw.lstrip(b"\x00")))
        if raw.lstrip(b"\x00") != raw
        else B58[0] * (len(raw) - len(raw.lstrip(b"\x00"))) + out
    )


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def wallet():
    key = SigningKey.generate()
    address = b58encode(bytes(key.verify_key))
    return key, address


@pytest.fixture
def auth(client, wallet):
    key, address = wallet
    nonce_response = client.get("/auth/nonce", params={"wallet_address": address}).json()
    signed = key.sign(nonce_response["message"].encode())
    signature = base64.b64encode(signed.signature).decode()

    response = client.post(
        "/auth/login",
        json={
            "wallet_address": address,
            "message": nonce_response["message"],
            "signature": signature,
        },
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}, address


def test_health(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["mode"] == "paper"


def test_login_rejects_bad_signature(client, wallet):
    _, address = wallet
    nonce_response = client.get("/auth/nonce", params={"wallet_address": address}).json()
    response = client.post(
        "/auth/login",
        json={
            "wallet_address": address,
            "message": nonce_response["message"],
            "signature": base64.b64encode(b"\x00" * 64).decode(),
        },
    )
    assert response.status_code == 401


def test_protected_routes_require_token(client):
    assert client.get("/portfolio").status_code == 401


def test_endpoints_return_expected_shapes(client, auth):
    headers, _ = auth

    portfolio = client.get("/portfolio", headers=headers).json()
    assert portfolio["equity_usd"] == 1000.0
    assert portfolio["open_positions"] == 0
    assert portfolio["win_rate"] is None

    state = client.get("/bot/state", headers=headers).json()
    assert state["state"] == "stopped"
    assert state["mode"] == "paper"

    assert client.get("/positions", headers=headers).json() == []
    assert client.get("/trades", headers=headers).json() == []
    assert isinstance(client.get("/logs", headers=headers).json(), list)
    assert client.get("/bot/pending-tx", headers=headers).json()["items"] == []

    settings = client.get("/bot/settings", headers=headers).json()
    assert settings["stop_loss_pct"] == 6.0
    assert settings["take_profit_pct"] == 12.0


def test_settings_update_is_persisted(client, auth):
    headers, _ = auth
    updated = client.put(
        "/bot/settings",
        headers=headers,
        json={"stop_loss_pct": 3.5, "max_open_positions": 3, "min_entry_score": 90},
    ).json()
    assert updated["stop_loss_pct"] == 3.5
    assert updated["max_open_positions"] == 3
    assert updated["min_entry_score"] == 90
    assert client.get("/bot/settings", headers=headers).json()["stop_loss_pct"] == 3.5


def test_start_stop_close_all_lifecycle(client, auth):
    headers, _ = auth

    started = client.post("/bot/start", headers=headers).json()
    assert started["state"] == "running"

    stopped = client.post("/bot/stop", headers=headers).json()
    assert stopped["state"] == "stopped"

    messages = [e["message"] for e in client.get("/logs", headers=headers).json()]
    assert any(m.startswith("AI TRADING STARTED") for m in messages)
    assert any(m.startswith("AI TRADING STOPPED") for m in messages)

    assert client.post("/bot/stop", headers=headers).status_code == 409
    assert client.post("/bot/close-all", headers=headers).status_code == 409
    assert (
        client.post(
            "/wallet/tx/submit", headers=headers, json={"signed_transaction": "x"}
        ).status_code
        == 409
    )
