"""Every user-facing money endpoint needs login, and one user can never touch another user's data.

Razorpay itself is faked (create_order / create_refund); webhooks are signed with a test secret
exactly like Razorpay signs them, so the real signature check runs.
"""
import hashlib
import hmac
import itertools
import json

import pytest

from app.config import settings
from app.payments import service as pay_service

WEBHOOK_SECRET = "whsec_test_secret"
_counter = itertools.count(1)


@pytest.fixture(autouse=True)
def fake_razorpay(monkeypatch):
    monkeypatch.setattr(settings, "razorpay_webhook_secret", WEBHOOK_SECRET)
    monkeypatch.setattr(settings, "razorpay_key_id", "rzp_test_x")

    def create_order(amount_rupees):
        n = next(_counter)
        # Real Razorpay ids are "order_" + 14 characters (20 total). Short fake ids hid a length bug once.
        return {"id": f"order_{n:014d}", "receipt": f"rcpt_{n}", "amount": round(amount_rupees * 100), "currency": "INR"}

    def create_refund(payment_id, amount_paise):
        return {"id": f"rfnd_{payment_id}", "amount": amount_paise}

    monkeypatch.setattr(pay_service, "create_order", create_order)
    monkeypatch.setattr(pay_service, "create_refund", create_refund)


def _signed_post(client, event: dict, event_id: str):
    raw = json.dumps(event).encode()
    sig = hmac.new(WEBHOOK_SECRET.encode(), raw, hashlib.sha256).hexdigest()
    return client.post(
        "/payments/webhook",
        content=raw,
        headers={"X-Razorpay-Signature": sig, "X-Razorpay-Event-Id": event_id, "Content-Type": "application/json"},
    )


def _paid_event(order_id: str, amount: int = 49900):
    return {
        "event": "payment.captured",
        "payload": {"payment": {"entity": {"id": f"pay_{order_id}", "order_id": order_id, "amount": amount, "created_at": 1_700_000_000}}},
    }


def _refund_processed_event(order_id: str, amount: int = 49900):
    return {
        "event": "refund.processed",
        "payload": {
            "refund": {"entity": {"id": f"rfnd_pay_{order_id}", "payment_id": f"pay_{order_id}", "amount": amount}},
            "payment": {"entity": {"order_id": order_id}},
        },
    }


def _register(client, email):
    res = client.post("/auth/register", json={"email": email, "password": "correct-horse-1"})
    assert res.status_code == 201
    return {"Authorization": f"Bearer {res.json()['access_token']}"}


@pytest.fixture
def alice(client):
    return _register(client, "alice@example.com")


@pytest.fixture
def bob(client):
    return _register(client, "bob@example.com")


def _buy_pro(client, headers, event_id):
    """Checkout, then the paid webhook. Returns the order id."""
    res = client.post("/subscriptions/checkout", json={"plan_id": "pro"}, headers=headers)
    assert res.status_code == 200, res.text
    order_id = res.json()["order_id"]
    assert _signed_post(client, _paid_event(order_id), event_id).json() == {"status": "ok"}
    return order_id


# ---------- authentication required ----------

PROTECTED = [
    ("GET", "/users/me", None),
    ("PATCH", "/users/me", {}),
    ("GET", "/subscriptions/me", None),
    ("POST", "/subscriptions/checkout", {"plan_id": "pro"}),
    ("GET", "/billing/history", None),
    ("GET", "/billing/invoices/order_x/pdf", None),
    ("POST", "/payments/create-order", {"amount": 10}),
    ("POST", "/payments/verify", {"razorpay_order_id": "o", "razorpay_payment_id": "p", "razorpay_signature": "s"}),
    ("GET", "/payments/status/order_x", None),
    ("POST", "/payments/order_x/refund", None),
]


@pytest.mark.parametrize("method,path,body", PROTECTED)
def test_endpoint_requires_login(client, method, path, body):
    res = client.request(method, path, json=body)
    assert res.status_code == 401, f"{method} {path} -> {res.status_code}"


def test_webhook_stays_open_to_razorpay_but_checks_signature(client):
    bad = client.post("/payments/webhook", content=b"{}", headers={"X-Razorpay-Signature": "nope", "X-Razorpay-Event-Id": "e1"})
    assert bad.status_code == 400  # rejected by signature, not by login (401)
    ok = _signed_post(client, {"event": "something.else"}, "e2")
    assert ok.status_code == 200


# ---------- real user, real data ----------

def test_new_user_starts_on_basic_with_no_history(client, alice):
    sub = client.get("/subscriptions/me", headers=alice).json()
    assert sub["plan_id"] == "basic"
    assert sub["user_id"].startswith("usr_")
    assert client.get("/billing/history", headers=alice).json() == {"items": []}


def test_order_is_stored_with_its_owner(client, alice, db):
    from sqlalchemy import select

    from app.payments.models import Payment
    from app.users.models import User

    order_id = client.post("/payments/create-order", json={"amount": 10}, headers=alice).json()["order_id"]
    payment = db.scalar(select(Payment).where(Payment.order_id == order_id))
    assert payment.user_id == db.scalar(select(User.user_id).where(User.email == "alice@example.com"))


def test_full_purchase_and_refund_flow_for_a_real_user(client, alice):
    order_id = _buy_pro(client, alice, "evt_paid_1")

    sub = client.get("/subscriptions/me", headers=alice).json()
    assert sub["plan_id"] == "pro" and sub["refundable_order_id"] == order_id

    items = client.get("/billing/history", headers=alice).json()["items"]
    assert [i["order_id"] for i in items] == [order_id] and items[0]["status"] == "paid"

    pdf = client.get(f"/billing/invoices/{order_id}/pdf", headers=alice)
    assert pdf.status_code == 200 and pdf.content.startswith(b"%PDF")  # works with no profile name set

    assert client.get(f"/payments/status/{order_id}", headers=alice).json()["status"] == "paid"
    assert client.post(f"/payments/{order_id}/refund", headers=alice).json()["status"] == "pending"

    assert _signed_post(client, _refund_processed_event(order_id), "evt_refund_1").json() == {"status": "ok"}
    assert client.get("/subscriptions/me", headers=alice).json()["plan_id"] == "basic"
    assert client.get("/billing/history", headers=alice).json()["items"][0]["status"] == "refunded"


# ---------- isolation between users ----------

def test_users_do_not_share_subscriptions_or_history(client, alice, bob):
    _buy_pro(client, alice, "evt_paid_a")
    assert client.get("/subscriptions/me", headers=alice).json()["plan_id"] == "pro"
    assert client.get("/subscriptions/me", headers=bob).json()["plan_id"] == "basic"
    assert client.get("/billing/history", headers=bob).json() == {"items": []}
    assert len(client.get("/billing/history", headers=alice).json()["items"]) == 1


def test_other_users_cannot_see_pay_or_refund_an_order(client, alice, bob):
    order_id = _buy_pro(client, alice, "evt_paid_a")

    assert client.get(f"/payments/status/{order_id}", headers=bob).status_code == 404
    assert client.post(f"/payments/{order_id}/refund", headers=bob).status_code == 404
    verify = {"razorpay_order_id": order_id, "razorpay_payment_id": "p", "razorpay_signature": "s"}
    assert client.post("/payments/verify", json=verify, headers=bob).status_code == 404
    # A refund by the wrong user must not have started anything for the real owner either.
    assert client.get("/subscriptions/me", headers=alice).json()["refund_status"] is None


def test_other_users_cannot_download_an_invoice(client, alice, bob):
    order_id = _buy_pro(client, alice, "evt_paid_a")
    assert client.get(f"/billing/invoices/{order_id}/pdf", headers=bob).status_code == 404
    assert client.get(f"/billing/invoices/{order_id}/pdf", headers=alice).status_code == 200


def test_not_owned_and_nonexistent_orders_look_the_same(client, alice, bob):
    order_id = _buy_pro(client, alice, "evt_paid_a")
    not_yours = client.get(f"/payments/status/{order_id}", headers=bob)
    missing = client.get("/payments/status/order_does_not_exist", headers=bob)
    assert not_yours.status_code == missing.status_code == 404
    assert not_yours.json() == missing.json()


def test_invoice_pdf_uses_profile_name_when_set(client, alice):
    client.patch("/users/me", headers=alice, json={"first_name": "Alice", "last_name": "Smith"})
    order_id = _buy_pro(client, alice, "evt_paid_a")
    assert client.get(f"/billing/invoices/{order_id}/pdf", headers=alice).status_code == 200


# ---------- CORS ----------

def _preflight(client, origin):
    return client.options(
        "/users/me",
        headers={"Origin": origin, "Access-Control-Request-Method": "GET", "Access-Control-Request-Headers": "authorization"},
    )


def test_cors_allows_localhost_with_credentials_and_echoes_origin(client):
    res = _preflight(client, "http://localhost:54321")
    assert res.headers["access-control-allow-origin"] == "http://localhost:54321"  # never "*"
    assert res.headers["access-control-allow-credentials"] == "true"


def test_cors_rejects_unknown_origins(client):
    res = _preflight(client, "https://evil.example.com")
    assert "access-control-allow-origin" not in res.headers
    assert client.get("/health", headers={"Origin": "https://evil.example.com"}).headers.get("access-control-allow-origin") is None
