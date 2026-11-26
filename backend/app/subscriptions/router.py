from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth.dependencies import get_current_user
from app.config import settings
from app.db import get_db
from app.payments import repository as pay_repo
from app.payments import service as pay_service
from app.payments.schemas import CreateOrderResponse
from app.subscriptions import repository
from app.subscriptions.plans import PLANS
from app.subscriptions.schemas import CheckoutRequest, PlanInfo, SubscriptionResponse
from app.users.models import User

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


def _plans() -> list[PlanInfo]:
    return [PlanInfo(id=k, **v) for k, v in PLANS.items()]


@router.get("/me", response_model=SubscriptionResponse)
def my_subscription(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    sub = repository.get_or_create(db, user.user_id)
    db.commit()
    refundable, refund_status = None, None
    if sub.plan_id == "pro":
        purchase = repository.latest_applied_purchase(db, user.user_id)
        payment = pay_repo.get_by_order(db, purchase.order_id) if purchase else None
        if payment and payment.status == "paid":
            refundable = payment.order_id
            refund = pay_repo.latest_refund(db, payment.order_id)
            refund_status = refund.status if refund else None
    return SubscriptionResponse(
        user_id=sub.user_id,
        plan_id=sub.plan_id,
        pro_until=sub.pro_until,
        refundable_order_id=refundable,
        refund_status=refund_status,
        plans=_plans(),
    )


@router.post("/checkout", response_model=CreateOrderResponse)
def checkout(
    body: CheckoutRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    plan = PLANS.get(body.plan_id)
    if plan is None or plan["price_rupees"] <= 0:
        raise HTTPException(status_code=400, detail="This plan cannot be purchased")
    if repository.get_or_create(db, user.user_id).plan_id == body.plan_id:
        raise HTTPException(status_code=409, detail="You are already on this plan")
    try:
        order = pay_service.create_order(plan["price_rupees"])
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="Could not create order with Razorpay")
    pay_repo.save_order(db, user.user_id, order["id"], order["receipt"], order["amount"], order["currency"])
    repository.add_purchase(db, order["id"], user.user_id, body.plan_id)
    return CreateOrderResponse(
        order_id=order["id"],
        amount=order["amount"],
        currency=order["currency"],
        key_id=settings.razorpay_key_id,
    )
