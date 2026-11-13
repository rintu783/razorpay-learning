from fastapi import APIRouter, HTTPException

from app.config import settings
from app.payments import service
from app.payments.schemas import (
    CreateOrderRequest,
    CreateOrderResponse,
    VerifyPaymentRequest,
    VerifyPaymentResponse,
)

router = APIRouter(prefix="/payments", tags=["payments"])


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
