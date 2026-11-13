from fastapi import APIRouter, HTTPException

from app.config import settings
from app.payments import service
from app.payments.schemas import CreateOrderRequest, CreateOrderResponse

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
