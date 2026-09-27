import os
import tempfile
from pathlib import Path

import pytest

TMP_DB = Path(tempfile.gettempdir()) / "memetrader_test.db"
TMP_DB.unlink(missing_ok=True)

os.environ["EXECUTION_MODE"] = "paper"
os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{TMP_DB.as_posix()}"
# park the background loop so tests drive tick() explicitly
os.environ["SCAN_INTERVAL_SECONDS"] = "3600"
os.environ["DEXSCREENER_CACHE_TTL"] = "0"
os.environ["SECRET_KEY"] = "test-secret"

from app.db import SessionLocal, engine, init_models  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
async def _database():
    await init_models()
    yield
    await engine.dispose()
    TMP_DB.unlink(missing_ok=True)


@pytest.fixture
def session_factory():
    return SessionLocal
