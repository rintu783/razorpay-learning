import json
import logging

from fastapi import APIRouter, Header, HTTPException, Request

from app.config import settings
from app.payments import service
from app.payments.schemas import (
    CreateOrderRequest,
    CreateOrderResponse,
    VerifyPaymentRequest,
    VerifyPaymentResponse,
)

log = logging.getLogger("payments.webhook")
router = APIRouter(prefix="/payments", tags=["payments"])

# Event IDs already handled. In-memory only: resets on restart (a DB would persist this).
_seen_events: set[str] = set()


@router.post("/create-order", response_model=CreateOrderResponse)
def create_order(body: CreateOrderRequest):
    try:
        order = service.create_order(body.amount)
    except RuntimeError as e:  # missing keys
        raise HTTPException(status_code=500, detail=str(e))
    except Exception:  # Razorpay/network error; don't leak details to the client
        raise HTTPException(status_code=502, detail="Could not create order with Razorpay")
    return CreateOrderResponse(
        order_id=order["id"],
        amount=order["amount"],
        currency=order["currency"],
        key_id=settings.razorpay_key_id,
    )


@router.post("/verify", response_model=VerifyPaymentResponse)
def verify_payment(body: VerifyPaymentRequest):
    try:
        ok = service.verify_signature(
            body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature
        )
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    # Only the backend decides "paid". (DB update would go here later.)
    return VerifyPaymentResponse(verified=ok, status="paid" if ok else "failed")


@router.post("/webhook")
async def webhook(
    request: Request,
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

    # Razorpay may retry/duplicate events; process each event ID once.
    if x_razorpay_event_id and x_razorpay_event_id in _seen_events:
        return {"status": "duplicate"}
    _seen_events.add(x_razorpay_event_id)

    event = json.loads(raw)
    name = event.get("event")
    if name in ("payment.captured", "order.paid", "payment.failed"):
        entity = event.get("payload", {}).get("payment", {}).get("entity", {})
        log.warning(
            "webhook %s order=%s payment=%s", name, entity.get("order_id"), entity.get("id")
        )
        # Later: update the order status in the DB here.
    return {"status": "ok"}  # reply 200 fast so Razorpay doesn't retry
