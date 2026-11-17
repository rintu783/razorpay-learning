from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.subscriptions.models import PlanPurchase, Subscription
from app.subscriptions.plans import PLANS


def get_or_create(db: Session, user_id: str) -> Subscription:
    sub = db.scalar(select(Subscription).where(Subscription.user_id == user_id))
    if sub is None:
        sub = Subscription(user_id=user_id, plan_id="basic")
        db.add(sub)
        db.flush()
    # Pro that has run out counts as Basic.
    if sub.plan_id == "pro" and sub.pro_until:
        # SQLite drops the timezone; values are stored as UTC.
        until = sub.pro_until.replace(tzinfo=timezone.utc) if sub.pro_until.tzinfo is None else sub.pro_until
        if until < datetime.now(timezone.utc):
            sub.plan_id, sub.pro_until = "basic", None
    return sub


def add_purchase(db: Session, order_id: str, user_id: str, plan_id: str) -> None:
    db.add(PlanPurchase(order_id=order_id, user_id=user_id, plan_id=plan_id))
    db.commit()


def get_purchase(db: Session, order_id: str) -> PlanPurchase | None:
    return db.scalar(select(PlanPurchase).where(PlanPurchase.order_id == order_id))


def apply_paid(db: Session, order_id: str) -> bool:
    """Called by the webhook when an order is paid. Upgrades once per order."""
    purchase = get_purchase(db, order_id)
    if purchase is None or purchase.applied:
        return False
    sub = get_or_create(db, purchase.user_id)
    sub.plan_id = purchase.plan_id
    sub.pro_until = datetime.now(timezone.utc) + timedelta(days=PLANS[purchase.plan_id]["days"])
    purchase.applied = True
    return True
