from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update

from app.auth.tokens import hash_refresh_token
from app.config import settings
from app.users.models import RefreshToken, User
from tests.conftest import EMAIL, PASSWORD

COOKIE = "__session"


def _login(client, email=EMAIL, password=PASSWORD):
    return client.post("/auth/login", json={"email": email, "password": password})


def _cookie(client) -> str:
    return client.cookies.get(COOKIE, path="/auth")


# ---------- register ----------

def test_register_returns_token_and_sets_secure_cookie(client):
    res = client.post("/auth/register", json={"email": EMAIL, "password": PASSWORD})
    assert res.status_code == 201
    body = res.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == settings.access_token_minutes * 60
    assert res.headers["cache-control"] == "no-store"
    set_cookie = res.headers["set-cookie"].lower()
    for flag in ("httponly", "secure", "samesite=lax", "path=/auth"):
        assert flag in set_cookie
    assert "refresh_token" not in body


def test_register_normalizes_email_and_stores_argon2_hash(client, db):
    client.post("/auth/register", json={"email": "  Alice@Example.COM ", "password": PASSWORD})
    user = db.scalar(select(User))
    assert user.email == "alice@example.com"
    assert user.password_hash.startswith("$argon2id$")
    assert PASSWORD not in user.password_hash


def test_register_duplicate_email_is_409_even_with_different_case(client, registered):
    res = client.post("/auth/register", json={"email": "ALICE@example.com", "password": PASSWORD})
    assert res.status_code == 409


def test_register_validation(client):
    bad = [
        {"email": "not-an-email", "password": PASSWORD},
        {"email": "b@example.com", "password": "short"},
        {"email": "b@example.com", "password": "x" * 129},
        {"email": "b@example.com"},
    ]
    for payload in bad:
        assert client.post("/auth/register", json=payload).status_code == 422, payload


# ---------- login ----------

def test_login_ok_with_any_email_case(client, registered):
    assert _login(client, email="ALICE@Example.com").status_code == 200


def test_login_wrong_password_and_unknown_email_give_identical_errors(client, registered):
    wrong_pw = _login(client, password="wrong-password")
    unknown = _login(client, email="ghost@example.com")
    assert wrong_pw.status_code == unknown.status_code == 401
    assert wrong_pw.json() == unknown.json() == {"detail": "Invalid email or password"}


# ---------- refresh ----------

def test_refresh_rotates_token(client, registered, db):
    old = _cookie(client)
    res = client.post("/auth/refresh")
    assert res.status_code == 200
    assert res.json()["access_token"]
    new = _cookie(client)
    assert new and new != old
    old_row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(old)))
    new_row = db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(new)))
    assert old_row.revoked_at is not None
    assert new_row.revoked_at is None
    assert old_row.family_id == new_row.family_id


def test_refresh_token_is_stored_only_as_hash(client, registered, db):
    raw = _cookie(client)
    rows = db.scalars(select(RefreshToken)).all()
    assert len(rows) == 1
    assert rows[0].token_hash != raw
    assert rows[0].token_hash == hash_refresh_token(raw)


def test_refresh_without_cookie_is_401(client):
    assert client.post("/auth/refresh").status_code == 401


def test_refresh_with_garbage_cookie_is_401(client):
    client.cookies.set(COOKIE, "garbage", path="/auth")
    assert client.post("/auth/refresh").status_code == 401


def test_replay_within_grace_window_is_rejected_but_session_survives(client, registered):
    old = _cookie(client)
    assert client.post("/auth/refresh").status_code == 200
    new = _cookie(client)

    client.cookies.set(COOKIE, old, path="/auth")  # a duplicate request carrying the old token
    assert client.post("/auth/refresh").status_code == 401

    client.cookies.set(COOKIE, new, path="/auth")  # the legitimate new token still works
    assert client.post("/auth/refresh").status_code == 200


def test_replay_after_grace_window_revokes_whole_family(client, registered, db):
    old = _cookie(client)
    client.post("/auth/refresh")
    new = _cookie(client)

    # Pretend the old token was revoked a minute ago, i.e. this replay is not a double request.
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.token_hash == hash_refresh_token(old))
        .values(revoked_at=datetime.now(timezone.utc) - timedelta(minutes=1))
    )
    db.commit()

    client.cookies.set(COOKIE, old, path="/auth")
    assert client.post("/auth/refresh").status_code == 401

    client.cookies.set(COOKIE, new, path="/auth")  # the victim's token died with the family
    assert client.post("/auth/refresh").status_code == 401
    assert all(r.revoked_at is not None for r in db.scalars(select(RefreshToken)).all())


def test_expired_refresh_token_is_401(client, registered, db):
    db.execute(update(RefreshToken).values(expires_at=datetime.now(timezone.utc) - timedelta(seconds=1)))
    db.commit()
    assert client.post("/auth/refresh").status_code == 401


def test_failed_refresh_clears_the_cookie(client):
    client.cookies.set(COOKIE, "garbage", path="/auth")
    res = client.post("/auth/refresh")
    assert "max-age=0" in res.headers["set-cookie"].lower()


def test_sessions_are_independent_per_login(client, registered, db):
    first = _cookie(client)
    _login(client)  # second login on the same user gets its own family
    families = {r.family_id for r in db.scalars(select(RefreshToken)).all()}
    assert len(families) == 2
    client.post("/auth/logout")  # logs out the second session only
    client.cookies.set(COOKIE, first, path="/auth")
    assert client.post("/auth/refresh").status_code == 200


# ---------- logout ----------

def test_logout_revokes_session_and_clears_cookie(client, registered, db):
    raw = _cookie(client)
    res = client.post("/auth/logout")
    assert res.status_code == 204
    assert "max-age=0" in res.headers["set-cookie"].lower()

    client.cookies.set(COOKIE, raw, path="/auth")
    assert client.post("/auth/refresh").status_code == 401
    assert all(r.revoked_at is not None for r in db.scalars(select(RefreshToken)).all())


def test_logout_without_cookie_is_still_204(client):
    assert client.post("/auth/logout").status_code == 204


# ---------- rate limit ----------

def test_login_is_rate_limited(client, monkeypatch):
    monkeypatch.setattr(settings, "rate_limit_enabled", True)
    codes = [_login(client, email="x@example.com", password="bad-password").status_code for _ in range(12)]
    assert 429 in codes
    assert codes[0] == 401
    limited = _login(client, email="x@example.com", password="bad-password")
    assert limited.status_code == 429
    assert int(limited.headers["retry-after"]) >= 1
