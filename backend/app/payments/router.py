import json
import logging

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.payments import repository, service
from app.subscriptions import repository as sub_repo
from app.payments.schemas import (
    CreateOrderRequest,
    CreateOrderResponse,
    PaymentStatusResponse,
    VerifyPaymentRequest,
    VerifyPaymentResponse,
)

log = logging.getLogger("payments")
router = APIRouter(prefix="/payments", tags=["payments"])

# Webhook event name -> our status
_EVENT_STATUS = {"payment.captured": "paid", "order.paid": "paid", "payment.failed": "failed"}


@router.post("/create-order", response_model=CreateOrderResponse)
def create_order(body: CreateOrderRequest, db: Session = Depends(get_db)):
    try:
        order = service.create_order(body.amount)
    except RuntimeError as e:  # missing keys
        raise HTTPException(status_code=500, detail=str(e))
    except Exception:  # Razorpay/network error; don't leak details to the client
        raise HTTPException(status_code=502, detail="Could not create order with Razorpay")
    repository.save_order(db, order["id"], order["receipt"], order["amount"], order["currency"])
    return CreateOrderResponse(
        order_id=order["id"],
        amount=order["amount"],
        currency=order["currency"],
        key_id=settings.razorpay_key_id,
    )


@router.post("/verify", response_model=VerifyPaymentResponse)
def verify_payment(body: VerifyPaymentRequest):
    """Checks the signature only. Does NOT change payment status (webhook does)."""
    try:
        ok = service.verify_signature(
            body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
        )
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    return VerifyPaymentResponse(verified=ok)


@router.get("/status/{order_id}", response_model=PaymentStatusResponse)
def payment_status(order_id: str, db: Session = Depends(get_db)):
    p = repository.get_by_order(db, order_id)
    if p is None:
        raise HTTPException(status_code=404, detail="Order not found")
    return PaymentStatusResponse(order_id=p.order_id, status=p.status, payment_id=p.payment_id)


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
    db.commit()
    log.warning("webhook %s order=%s -> %s (changed=%s)", name, payment.order_id, payment.status, changed)
    return {"status": "ok"}  # reply 200 fast so Razorpay doesn't retry
