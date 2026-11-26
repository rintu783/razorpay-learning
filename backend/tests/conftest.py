"""Test setup. Runs against a separate Postgres database (razorpay_test) in the same docker container.

The database is created if missing and migrated with Alembic, so the tests also check the migrations.
Every test starts with empty tables. Start Postgres first:  docker compose up -d
"""
import os
from pathlib import Path

import psycopg
import pytest
from sqlalchemy.engine import make_url

TEST_DB_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://razorpay:razorpay_dev_password@localhost:5433/razorpay_test",
)
_url = make_url(TEST_DB_URL)
# Tables are truncated between tests. Refuse to run against anything that is not clearly a test database.
assert _url.database and _url.database.endswith("_test"), "TEST_DATABASE_URL must point to a *_test database"

# Must be set before any `app` module is imported, because settings are read at import time.
os.environ["DATABASE_URL"] = TEST_DB_URL
os.environ.setdefault("JWT_SECRET", "test-secret-test-secret-test-secret-1234")
os.environ["RATE_LIMIT_ENABLED"] = "false"
os.environ["COOKIE_SECURE"] = "true"
os.environ["COOKIE_SAMESITE"] = "lax"

EMAIL = "alice@example.com"
PASSWORD = "correct-horse-1"


def _create_database_if_missing() -> None:
    with psycopg.connect(
        host=_url.host, port=_url.port, user=_url.username, password=_url.password,
        dbname="postgres", autocommit=True,
    ) as conn:
        exists = conn.execute("select 1 from pg_database where datname = %s", (_url.database,)).fetchone()
        if not exists:
            conn.execute(f'create database "{_url.database}"')


@pytest.fixture(scope="session", autouse=True)
def _migrated_db():
    _create_database_if_missing()
    from alembic import command
    from alembic.config import Config

    backend = Path(__file__).resolve().parent.parent
    cfg = Config(str(backend / "alembic.ini"))
    cfg.set_main_option("script_location", str(backend / "alembic"))
    command.upgrade(cfg, "head")


@pytest.fixture(autouse=True)
def _clean_tables(_migrated_db):
    from sqlalchemy import text

    from app.db import engine

    with engine.begin() as conn:
        names = conn.execute(
            text("select tablename from pg_tables where schemaname='public' and tablename <> 'alembic_version'")
        ).scalars().all()
        conn.execute(text("truncate " + ", ".join(f'"{n}"' for n in names) + " restart identity cascade"))
    yield


@pytest.fixture
def client():
    from fastapi.testclient import TestClient

    from app.main import app

    # https, because the refresh cookie is Secure and httpx only sends Secure cookies over https.
    with TestClient(app, base_url="https://testserver") as c:
        yield c


@pytest.fixture
def db():
    from app.db import SessionLocal

    with SessionLocal() as session:
        yield session


@pytest.fixture
def registered(client):
    """A registered user. Returns (access_token, auth_headers); the client holds the refresh cookie."""
    res = client.post("/auth/register", json={"email": EMAIL, "password": PASSWORD})
    assert res.status_code == 201
    token = res.json()["access_token"]
    return token, {"Authorization": f"Bearer {token}"}
