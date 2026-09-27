# mobile/ — Flutter client

UI + REST + WebSocket client for the FastAPI trading backend.

**Zero trading logic lives here.** The app never computes a score, a P&L, a TP
or a stop. The Python engine decides everything; Flutter only renders backend
state and sends user commands.

## Run it

Backend pehle chalu karo (`http://127.0.0.1:8000`), phir:

```bash
# Chrome / web (localhost backend)
flutter run -d chrome

# ya static build serve karo
flutter build web
python -m http.server 8080 --directory build/web
```

Non-default backend ke liye:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=https://abc.ngrok.io
# Android emulator: http://10.0.2.2:8000
# Physical phone  : http://<your-lan-ip>:8000
```

Login screen pe debug builds me **USE DEV WALLET** button aata hai jo ek
throwaway devnet key generate karta hai — Phantom extension ke bina paper
trading test karne ke liye. Release builds me wo button hidden hai.

## Bottom navigation

```
Wallet   Trade   AI   History   More
```

| Screen | Kya dikhata hai | Endpoints |
| --- | --- | --- |
| Wallet | address, available balance, all-time P&L %, engine status, START/STOP, CLOSE ALL, AI log stream | `GET /portfolio`, `GET /wallet`, `WS /ws/stream`, `GET /logs` |
| Trade | live opportunities: symbol, price, liquidity, volume, AI score, momentum, safety, blocked reasons | `GET /market/opportunities` |
| AI | bot state, tokens scanned, opportunities, open trades, today's P&L, risk limits | `GET /bot/state`, `POST /bot/start\|stop\|close-all`, `GET /bot/settings` |
| History | Positions / All / Deposits / Withdrawals tabs with entry, exit, qty, P&L, exit reason | `GET /positions?status=open\|closed`, `GET /trades` |
| More | execution mode, WS status, API status, chain, logout | `GET /wallet`, `GET /bot/settings` |

## Auth flow

```
GET /auth/nonce?wallet_address=...   -> {nonce, message}
sign the message (ed25519, base64)    -> LocalSigner
POST /auth/login {wallet,message,sig} -> JWT
JWT in flutter_secure_storage
```

The seed never leaves the device, is never persisted, and is never sent to the
backend. The backend only ever receives the derived public key and the
signature, verified with PyNaCl.

## STOP vs CLOSE ALL

Deliberately separate, and the UI says so:

- **STOP** → `POST /bot/stop` → no new BUYs. Open positions keep being managed
  (TP / SL / trailing).
- **CLOSE ALL** → `POST /bot/close-all` → exits every open position now.

## Execution mode

Paper is the backend default (`EXECUTION_MODE=paper`). Live Jupiter execution
returns an *unsigned* transaction for the wallet to sign, so unattended
auto-trading needs a delegated session signer (`has_session_key`). The client
has the submit path (`POST /wallet/tx/submit`) but it is not wired to a UI yet —
that is deliberate, not an oversight.

## Tests

```bash
flutter analyze
flutter test
```

56 tests: model parsing against real backend shapes, REST contract (paths,
query params, envelopes, error codes), and Ed25519 signing.

## Notes

- `pubspec.lock` is committed on purpose (application, not a package).
- `mobile/build/` is ignored.
- The APK build needs a capped Gradle heap; see `android/gradle.properties`.
