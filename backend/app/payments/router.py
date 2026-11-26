import json
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user
from app.config import settings
from app.db import get_db
from app.billing import repository as billing_repo
from app.payments import repository, service
from app.subscriptions import repository as sub_repo
from app.users.models import User
from app.payments.schemas import (
    CreateOrderRequest,
    CreateOrderResponse,
    PaymentStatusResponse,
    RefundResponse,
    VerifyPaymentRequest,
    VerifyPaymentResponse,
)

log = logging.getLogger("payments")
router = APIRouter(prefix="/payments", tags=["payments"])

# Webhook event name -> our status
_EVENT_STATUS = {"payment.captured": "paid", "order.paid": "paid", "payment.failed": "failed"}
_REFUND_EVENT_STATUS = {
    "refund.created": "pending",
    "refund.processed": "processed",
    "refund.failed": "failed",
}


@router.post("/create-order", response_model=CreateOrderResponse)
def create_order(
    body: CreateOrderRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        order = service.create_order(body.amount)
    except RuntimeError as e:  # missing keys
        raise HTTPException(status_code=500, detail=str(e))
    except Exception:  # Razorpay/network error; don't leak details to the client
        raise HTTPException(status_code=502, detail="Could not create order with Razorpay")
    repository.save_order(db, user.user_id, order["id"], order["receipt"], order["amount"], order["currency"])
    return CreateOrderResponse(
        order_id=order["id"],
        amount=order["amount"],
        currency=order["currency"],
        key_id=settings.razorpay_key_id,
    )


@router.post("/verify", response_model=VerifyPaymentResponse)
def verify_payment(
    body: VerifyPaymentRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Checks the signature only. Does NOT change payment status (webhook does)."""
    if repository.get_owned(db, body.razorpay_order_id, user.user_id) is None:
        raise HTTPException(status_code=404, detail="Order not found")
    try:
        ok = service.verify_signature(
            body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
        )
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    return VerifyPaymentResponse(verified=ok)


@router.get("/status/{order_id}", response_model=PaymentStatusResponse)
def payment_status(
    order_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    p = repository.get_owned(db, order_id, user.user_id)
    if p is None:
        raise HTTPException(status_code=404, detail="Order not found")
    return PaymentStatusResponse(order_id=p.order_id, status=p.status, payment_id=p.payment_id)


@router.post("/{order_id}/refund", response_model=RefundResponse)
def refund_order(
    order_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Full refund. Only starts it; the refund webhook updates the status."""
    payment = repository.get_owned(db, order_id, user.user_id)
    if payment is None:
        raise HTTPException(status_code=404, detail="Order not found")
    if payment.status != "paid" or not payment.payment_id:
        raise HTTPException(status_code=409, detail=f"Only paid orders can be refunded (status: {payment.status})")
    if repository.has_open_refund(db, order_id):
        raise HTTPException(status_code=409, detail="A refund for this order is already in progress or done")
    try:
        r = service.create_refund(payment.payment_id, payment.amount)
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception:
        log.exception("refund failed order=%s", order_id)
        raise HTTPException(status_code=502, detail="Razorpay could not create the refund")
    refund = repository.upsert_refund(
        db, r["id"], order_id, payment.payment_id, r.get("amount", payment.amount), "pending"
    )
    db.commit()
    return RefundResponse(
        refund_id=refund.refund_id, order_id=order_id, amount=refund.amount, status=refund.status
    )


# No login here: Razorpay calls this, not a user. The HMAC signature check below is the authentication.
@router.post("/webhook")
async def webhook(
    request: Request,
    db: Session = Depends(get_db),
    x_razorpay_signature: str = Header(default=""),
    x_razorpay_event_id: str = Header(default=""),
):
    raw = await request.body()  # raw bytes: required for the signature check
    try:
        ok = service.verify_webhook_signature(raw, x_razorpay_signature)
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    if not ok:
        raise HTTPException(status_code=400, detail="Invalid signature")
    if not x_razorpay_event_id:
        raise HTTPException(status_code=400, detail="Missing event id")

    event = json.loads(raw)
    name = event.get("event", "")
    if name in _REFUND_EVENT_STATUS:
        return _handle_refund_event(db, event, name, x_razorpay_event_id)
    new_status = _EVENT_STATUS.get(name)
    if new_status is None:
        return {"status": "ignored"}

    # Same transaction: record the event id + update status. A repeat event is skipped.
    if not repository.record_event(db, x_razorpay_event_id, name):
        return {"status": "duplicate"}

    entity = event.get("payload", {}).get("payment", {}).get("entity", {})
    payment = repository.get_by_order(db, entity.get("order_id", ""))
    if payment is None:
        db.commit()
        log.warning("webhook %s for unknown order %s", name, entity.get("order_id"))
        return {"status": "unknown_order"}
    if new_status == "paid" and entity.get("amount") != payment.amount:
        db.commit()
        log.error("amount mismatch order=%s expected=%s got=%s",
                  payment.order_id, payment.amount, entity.get("amount"))
        return {"status": "amount_mismatch"}

    changed = repository.apply_status(db, payment, new_status, entity.get("id"))
    if payment.status == "paid":
        sub_repo.apply_paid(db, payment.order_id)  # upgrade the plan (once per order)
        billing_repo.create_invoice(db, payment, _paid_at(entity))  # once per order
    db.commit()
    log.warning("webhook %s order=%s -> %s (changed=%s)", name, payment.order_id, payment.status, changed)
    return {"status": "ok"}  # reply 200 fast so Razorpay doesn't retry


def _paid_at(entity: dict):
    """Payment time from Razorpay's payload (unix seconds), or None to use now."""
    ts = entity.get("created_at")
    return datetime.fromtimestamp(ts, tz=timezone.utc) if isinstance(ts, (int, float)) else None


def _handle_refund_event(db: Session, event: dict, name: str, event_id: str) -> dict:
    if not repository.record_event(db, event_id, name):
        return {"status": "duplicate"}
    payload = event.get("payload", {})
    refund_e = payload.get("refund", {}).get("entity", {})
    pay_e = payload.get("payment", {}).get("entity", {})
    payment = (
        repository.get_by_order(db, pay_e.get("order_id", ""))
        or repository.get_by_payment_id(db, refund_e.get("payment_id", ""))
    )
    if payment is None or not refund_e.get("id"):
        db.commit()
        log.warning("webhook %s for unknown payment %s", name, refund_e.get("payment_id"))
        return {"status": "unknown_payment"}

    status = _REFUND_EVENT_STATUS[name]
    refund = repository.upsert_refund(
        db, refund_e["id"], payment.order_id, refund_e.get("payment_id", ""), refund_e.get("amount", 0), status
    )
    # Only a fully processed refund ends the purchase (partial refunds from the dashboard do not).
    if refund.status == "processed" and refund.amount == payment.amount:
        repository.apply_status(db, payment, "refunded", None)
        sub_repo.revoke_for_order(db, payment.order_id)
    db.commit()
    log.warning("webhook %s order=%s refund=%s -> %s", name, payment.order_id, refund.refund_id, refund.status)
    return {"status": "ok"}
