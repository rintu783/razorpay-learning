from datetime import datetime, timedelta, timezone

import jwt
from sqlalchemy import delete

from app.auth.tokens import create_access_token
from app.config import settings
from app.users.models import User
from tests.conftest import EMAIL


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _token(claims: dict, secret: str | None = None) -> str:
    return jwt.encode(claims, secret or settings.jwt_secret, algorithm="HS256")


# ---------- get_current_user (exercised through /users/me) ----------

def test_no_token_is_401_with_www_authenticate(client):
    res = client.get("/users/me")
    assert res.status_code == 401
    assert res.headers["www-authenticate"] == "Bearer"


def test_garbage_token_is_401(client):
    assert client.get("/users/me", headers=_bearer("not.a.jwt")).status_code == 401


def test_wrong_scheme_is_401(client, registered):
    token, _ = registered
    assert client.get("/users/me", headers={"Authorization": f"Basic {token}"}).status_code == 401


def test_expired_access_token_is_401(client, registered, db):
    user_id = db.query(User).one().user_id
    past = datetime.now(timezone.utc) - timedelta(minutes=1)
    token = _token({"sub": user_id, "typ": "access", "exp": past})
    assert client.get("/users/me", headers=_bearer(token)).status_code == 401


def test_token_signed_with_other_secret_is_401(client, registered, db):
    user_id = db.query(User).one().user_id
    future = datetime.now(timezone.utc) + timedelta(minutes=5)
    token = _token({"sub": user_id, "typ": "access", "exp": future}, secret="x" * 40)
    assert client.get("/users/me", headers=_bearer(token)).status_code == 401


def test_alg_none_token_is_401(client, registered, db):
    user_id = db.query(User).one().user_id
    token = jwt.encode({"sub": user_id, "typ": "access", "exp": 9999999999}, key=None, algorithm="none")
    assert client.get("/users/me", headers=_bearer(token)).status_code == 401


def test_token_with_wrong_type_is_401(client, registered, db):
    user_id = db.query(User).one().user_id
    future = datetime.now(timezone.utc) + timedelta(minutes=5)
    token = _token({"sub": user_id, "typ": "refresh", "exp": future})
    assert client.get("/users/me", headers=_bearer(token)).status_code == 401


def test_token_for_deleted_user_is_401(client, registered, db):
    token, headers = registered
    db.execute(delete(User))
    db.commit()
    assert client.get("/users/me", headers=headers).status_code == 401


# ---------- GET /users/me ----------

def test_me_returns_account_with_empty_profile(client, registered):
    _, headers = registered
    body = client.get("/users/me", headers=headers).json()
    assert body["email"] == EMAIL
    assert body["user_id"].startswith("usr_")
    assert body["first_name"] is None and body["last_name"] is None and body["phone"] is None
    assert "password" not in str(body).lower()


def test_each_user_sees_only_their_own_account(client, registered):
    _, alice = registered
    other = client.post("/auth/register", json={"email": "bob@example.com", "password": "another-pass-9"})
    bob = _bearer(other.json()["access_token"])
    assert client.get("/users/me", headers=alice).json()["email"] == EMAIL
    assert client.get("/users/me", headers=bob).json()["email"] == "bob@example.com"


# ---------- PATCH /users/me ----------

def test_patch_requires_auth(client):
    assert client.patch("/users/me", json={"first_name": "A"}).status_code == 401


def test_patch_updates_profile(client, registered):
    _, headers = registered
    res = client.patch(
        "/users/me",
        headers=headers,
        json={"first_name": "  Alice ", "last_name": "Smith", "phone": "+91 98765-43210"},
    )
    assert res.status_code == 200
    assert res.json()["first_name"] == "Alice"
    assert client.get("/users/me", headers=headers).json()["phone"] == "+91 98765-43210"


def test_patch_is_partial_and_empty_string_clears(client, registered):
    _, headers = registered
    client.patch("/users/me", headers=headers, json={"first_name": "Alice", "last_name": "Smith"})
    body = client.patch("/users/me", headers=headers, json={"last_name": ""}).json()
    assert body["first_name"] == "Alice"  # omitted, unchanged
    assert body["last_name"] is None  # cleared


def test_patch_cannot_change_email_password_or_id(client, registered):
    _, headers = registered
    for field in ("email", "password_hash", "user_id"):
        res = client.patch("/users/me", headers=headers, json={field: "x@example.com"})
        assert res.status_code == 422, field
    assert client.get("/users/me", headers=headers).json()["email"] == EMAIL


def test_patch_validation(client, registered):
    _, headers = registered
    assert client.patch("/users/me", headers=headers, json={"phone": "abc"}).status_code == 422
    assert client.patch("/users/me", headers=headers, json={"first_name": "x" * 61}).status_code == 422


def test_access_token_helper_roundtrip(client, registered, db):
    user_id = db.query(User).one().user_id
    assert client.get("/users/me", headers=_bearer(create_access_token(user_id))).status_code == 200
