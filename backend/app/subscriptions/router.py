from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.payments import repository as pay_repo
from app.payments import service as pay_service
from app.payments.schemas import CreateOrderResponse
from app.subscriptions import repository
from app.subscriptions.plans import DEMO_USER, PLANS
from app.subscriptions.schemas import CheckoutRequest, PlanInfo, SubscriptionResponse

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


def _plans() -> list[PlanInfo]:
    return [PlanInfo(id=k, **v) for k, v in PLANS.items()]


@router.get("/me", response_model=SubscriptionResponse)
def my_subscription(db: Session = Depends(get_db)):
    sub = repository.get_or_create(db, DEMO_USER)
    db.commit()
    return SubscriptionResponse(
        user_id=sub.user_id, plan_id=sub.plan_id, pro_until=sub.pro_until, plans=_plans()
    )


@router.post("/checkout", response_model=CreateOrderResponse)
def checkout(body: CheckoutRequest, db: Session = Depends(get_db)):
    plan = PLANS.get(body.plan_id)
    if plan is None or plan["price_rupees"] <= 0:
        raise HTTPException(status_code=400, detail="This plan cannot be purchased")
    if repository.get_or_create(db, DEMO_USER).plan_id == body.plan_id:
        raise HTTPException(status_code=409, detail="You are already on this plan")
    try:
        order = pay_service.create_order(plan["price_rupees"])
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="Could not create order with Razorpay")
    pay_repo.save_order(db, order["id"], order["receipt"], order["amount"], order["currency"])
    repository.add_purchase(db, order["id"], DEMO_USER, body.plan_id)
    return CreateOrderResponse(
        order_id=order["id"],
        amount=order["amount"],
        currency=order["currency"],
        key_id=settings.razorpay_key_id,
    )
