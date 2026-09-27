# AI Meme Trader

Android app + FastAPI backend jahan AI khud Solana meme-coins scan karta hai,
score karta hai, risk check karta hai, aur BUY / HOLD / SELL / TP / SL / trailing
exit manage karta hai — jab tak user STOP na dabaye.

**Default mode = paper trading.** Koi private key, koi withdrawal permission,
koi real paisa nahi lagta. Execution layer modular hai, isliye real Jupiter +
Phantom Connect signing ke liye sirf `EXECUTION_MODE` switch karna hota hai.

```
FLUTTER ANDROID
      │  HTTPS + JWT
      ▼
FASTAPI ── Redis (state) ── PostgreSQL (users, positions, trades, logs)
      │
      ├─ SCANNER   DexScreener   (discovery + market data, no key)
      ├─ ENGINE    filters → scoring → risk → entry → exits
      ├─ EXECUTION paper  |  jupiter (unsigned tx → app signs)
      ├─ CHAIN     Helius       (RPC, balances, holder stats)
      └─ AI        Gemini       (optional narrative/context only)
```

---

## 1. Quick start (2 commands, no API keys)

```bash
cd backend
python -m venv .venv
.\.venv\Scripts\python -m pip install -e ".[dev]"      # Windows
# python -m venv .venv && pip install -e ".[dev]"       # macOS/Linux

.\.venv\Scripts\python -m uvicorn app.main:app --reload
```

Ab `http://localhost:8000/docs` kholo. Default `.env` values ke saath
`EXECUTION_MODE=paper` hai aur SQLite use hota hai — Postgres ki zarurat nahi.

Bina kisi wallet ke end-to-end loop test:

```bash
.\.venv\Scripts\python -m pytest -q          # 52 tests
```

Production ke liye:

```bash
cp .env.example .env
docker compose up -d                          # postgres + redis
# .env me DATABASE_URL=postgresql+asyncpg://memetrader:memetrader@localhost:5432/memetrader
```

---

## 2. Repo layout

```
memetrader/
├── docker-compose.yml          postgres + redis
├── .env.example                every key, nothing hardcoded
└── backend/
    ├── pyproject.toml
    ├── app/
    │   ├── main.py             FastAPI app + lifespan
    │   ├── config.py           pydantic-settings
    │   ├── db.py               async engine, UTCDateTime type
    │   ├── models.py           8 tables
    │   ├── schemas.py          request/response models
    │   ├── deps.py             bearer auth -> User
    │   ├── runtime.py          shared clients + per-user bot instances
    │   ├── core/security.py    Phantom nonce + ed25519 verify + JWT
    │   ├── clients/            dexscreener, jupiter, helius, gemini
    │   ├── engine/
    │   │   ├── types.py        TokenSnapshot, Candidate, ExitSignal, ...
    │   │   ├── scanner.py      discovery -> snapshots -> candidates
    │   │   ├── filters.py      hard safety blocks + soft penalties
    │   │   ├── scoring.py      0-100 opportunity score
    │   │   ├── risk.py         sizing + circuit breakers
    │   │   ├── exits.py        TP / SL / trailing / emergency
    │   │   ├── exits_params.py TP/SL/trailing maths
    │   │   ├── pnl.py          equity, cash, P&L, win rate
    │   │   └── bot.py          the START -> ... -> STOP loop
    │   ├── execution/
    │   │   ├── base.py         Executor protocol + NeedsClientSignature
    │   │   ├── paper.py        default: simulated fills
    │   │   └── jupiter_executor.py
    │   ├── service/store.py    all persistence
    │   └── api/routes/         auth, wallet, bot, market, positions, ws
    └── tests/                  52 tests, zero network, zero keys
```

---

## 3. Bot lifecycle

```
START AI TRADING
   │
   ├── SCAN     DexScreener boosts feeds -> fresh solana tokens
   ├── FILTER   liquidity / volume / buy-sell / age / pump / metadata
   ├── SCORE    liquidity 15 | volume accel 15 | momentum 15 | buy pressure 10
   │            whale 15 | holders 10 | market 10 | safety 10  = 100
   ├── RISK     daily-loss halt, max positions, price impact, size
   ├── BUY      paper fill  |  jupiter quote -> unsigned tx -> app signs
   ├── MONITOR  mark price, ratchet the trailing stop
   ├── EXIT     SL → trailing → deep loss → TP → score collapse → max hold
   │            (+ emergency: whale dump, liquidity collapse)
   ├── SELL
   └── RESCAN   cooldown thoda, phir wapas SCAN

STOP AI TRADING   → no new BUYs. Open positions still monitored + managed.
CLOSE ALL         → every open position exited. Alag command, alag button.
```

`STOP` aur `CLOSE ALL` alag hain isliye galti se STOP dabane par positions
uncontrolled nahi chhoot-te.

---

## 4. Risk controls

| Control | Setting | Default |
| --- | --- | --- |
| Risk per trade | `RISK_PER_TRADE_PCT` | 1% of equity (capped 25%) |
| Max open positions | `MAX_OPEN_POSITIONS` | 5 |
| Max daily loss | `MAX_DAILY_LOSS_PCT` | 5% → halts new entries |
| Take profit | `TAKE_PROFIT_PCT` | 12% |
| Stop loss | `STOP_LOSS_PCT` | 6% |
| Trailing | `TRAILING_ACTIVATION_PCT` / `TRAILING_DROP_PCT` | +8% / −4% |
| Max hold | `MAX_HOLD_MINUTES` | 240 |
| Min entry score | `MIN_ENTRY_SCORE` | 80 |
| Re-entry cooldown | `REENTRY_COOLDOWN_MINUTES` | 15 |

Per-user overrides `PUT /bot/settings` se.

---

## 5. API

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/auth/nonce?wallet_address=` | nonce + message to sign |
| POST | `/auth/login` | signature verify → JWT |
| GET | `/wallet` | SOL/USDC balance, execution mode |
| POST | `/wallet/tx/submit` | app posts a Phantom-signed tx |
| GET | `/bot/state` | Home + AI screen payload |
| POST | `/bot/start` `\|` `/bot/stop` `\|` `/bot/close-all` | the three controls |
| GET/PUT | `/bot/settings` | risk config |
| GET | `/bot/pending-tx` | unsigned txs waiting for a signature |
| GET | `/market/opportunities` | live ranked candidates |
| GET | `/portfolio` | equity, cash, P&L, win rate |
| GET | `/positions?status=open\|closed` | Positions screen |
| GET | `/trades` `/logs` | Trade + Logs screens |
| WS | `/ws/stream?token=` | live state + latest log lines |

---

## 6. Wallet & signing (Phantom Connect)

Design constraint: **backend ke paas private key kabhi nahi hoti.**

1. App Phantom Connect embedded wallet use karta hai → user ka public key milta hai.
2. User ek message sign karta hai → backend ed25519 verify karke JWT deta hai.
3. `EXECUTION_MODE=jupiter` par bot har swap ke liye Jupiter quote leta hai aur
   backend `NeedsClientSignature(unsigned_tx)` raise karta hai.
4. App `GET /bot/pending-tx` se unsigned tx uthata hai, Phantom se sign karta hai,
   aur `POST /wallet/tx/submit` par bhejta hai. Backend confirm karke log karta hai.

Isi liye unattended `START → trade → STOP` flow **paper mode me poora chalta
hai**, aur real mode me app ko signature bhejni padti hai — jab tak Phantom ka
session/embedded signing model use karke keyless automation enable nahi hota.
Private key server side nahi, withdrawal permission kisi bhi API key me nahi.

---

## 7. Gemini ka role

Gemini **trading brain nahi hai.** Sirf narrative/context (logs, trade screen
explanations). Buy/sell decision pure quant engine + risk engine se aata hai,
isliye execution LLM latency par depend nahi karta. `GEMINI_API_KEY` set nahi
hoga to bhi sab chalta hai.

---

## 8. Security notes

- Koi private key, seed phrase, ya exchange withdrawal permission codebase me nahi.
- Saare keys sirf `.env` me (`.gitignore` me hai).
- Helius/Jupiter/DexScreener sirf market data + swaps ke liye.
- Trade sizes aur stop levels server-side risk engine enforce karta hai, app nahi.
