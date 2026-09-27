# mobile/ — Flutter Android app (not built yet)

Backend core ready hai (`../backend`). Ye folder Flutter client ke liye hai.
Scaffold yahan se banega, taaki MVP ka next step sirf UI ho.

## Bottom navigation

```
Home   Trade   AI   Logs   More
```

## Screens → backend endpoints

| Screen | Kya dikhata hai | Endpoints |
| --- | --- | --- |
| 1. Wallet / Connect | Phantom Connect, sign-in | `GET /auth/nonce`, `POST /auth/login`, `GET /wallet` |
| 2. Home | equity, today's P&L, AI status, open trades, recent trades | `WS /ws/stream`, `GET /portfolio` |
| 3. Trade | AI-discovered tokens, score breakdown, entry/TP/SL preview | `GET /market/opportunities` |
| 4. AI Bot | ACTIVE/INACTIVE, tokens scanned, opportunities, win rate, START/STOP/CLOSE ALL | `GET /bot/state`, `POST /bot/start|stop|close-all`, `GET/PUT /bot/settings` |
| 5. Positions | open + closed, unrealised P&L, exit reason | `GET /positions?status=open\|closed` |
| 6. AI Trade Logs | timestamped BUY/SELL + score + P&L + reason | `GET /logs`, `GET /trades` |
| 7. More / Settings | execution mode, risk config, disconnect | `GET /bot/settings`, `PUT /bot/settings` |

## Phantom Connect flow (Android)

1. Phantom mobile deep link se wallet connect (`phantom_connect` / universal link).
   Mobile app ke andar Phantom SDK embed karna zaroori nahi — deep link + redirect
   kaafi hai MVP ke liye.
2. Backend `GET /auth/nonce` → message → `signMessage` → `POST /auth/login` → JWT.
   JWT `flutter_secure_storage` me.
3. `WS /ws/stream?token=<jwt>` se Home/AI screens live update.
4. `EXECUTION_MODE=jupiter` hone par `GET /bot/pending-tx` poll karo, unsigned tx
   Phantom se sign karo, `POST /wallet/tx/submit`.

## State management

`provider` ya `riverpod` — zyada se zyada ek `BotStore` (websocket + bot state),
ek `AuthStore`, ek `PortfolioStore`. Screens polling nahi karengi, WS karega.

## MVP rule

UI polish baad me. Pehle ye chalna chahiye: connect → START → opportunity list
update hoti rehti hai → position khulti hai → TP/SL par band hoti hai → STOP.
