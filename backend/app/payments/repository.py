"""All database access for payments lives here."""
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.payments.models import Payment, Refund, WebhookEvent

# Allowed status moves. "failed" may become "paid" (retry). "paid" can only become "refunded".
_ALLOWED = {
    "created": {"paid", "failed"},
    "failed": {"paid"},
    "paid": {"refunded"},
    "refunded": set(),
}


def save_order(db: Session, user_id: str, order_id: str, receipt: str, amount: int, currency: str) -> Payment:
    p = Payment(user_id=user_id, order_id=order_id, receipt=receipt, amount=amount, currency=currency)
    db.add(p)
    db.commit()
    return p


def get_by_order(db: Session, order_id: str) -> Payment | None:
    return db.scalar(select(Payment).where(Payment.order_id == order_id))


def get_owned(db: Session, order_id: str, user_id: str) -> Payment | None:
    """The order, only if it belongs to this user. Callers answer 404 for both 'missing' and 'not yours'."""
    return db.scalar(select(Payment).where(Payment.order_id == order_id, Payment.user_id == user_id))


def record_event(db: Session, event_id: str, event_type: str) -> bool:
    """Returns False if this event_id was already processed."""
    db.add(WebhookEvent(event_id=event_id, event_type=event_type))
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        return False
    return True


def apply_status(db: Session, payment: Payment, new_status: str, payment_id: str | None) -> bool:
    """Move to new_status if the transition is allowed. Returns True if changed."""
    if new_status not in _ALLOWED[payment.status]:
        return False
    payment.status = new_status
    if payment_id:
        payment.payment_id = payment_id
    return True


def get_by_payment_id(db: Session, payment_id: str) -> Payment | None:
    return db.scalar(select(Payment).where(Payment.payment_id == payment_id))


def latest_refund(db: Session, order_id: str) -> Refund | None:
    return db.scalar(select(Refund).where(Refund.order_id == order_id).order_by(Refund.id.desc()))


def has_open_refund(db: Session, order_id: str) -> bool:
    """True if a refund is pending or already processed (blocks a second refund)."""
    return db.scalar(
        select(Refund.id).where(Refund.order_id == order_id, Refund.status.in_(["pending", "processed"]))
    ) is not None


def upsert_refund(
    db: Session, refund_id: str, order_id: str, payment_id: str, amount: int, status: str
) -> Refund:
    """Used by both the refund endpoint and the webhook (either may arrive first)."""
    r = db.scalar(select(Refund).where(Refund.refund_id == refund_id))
    if r is None:
        r = Refund(refund_id=refund_id, order_id=order_id, payment_id=payment_id, amount=amount, status=status)
        db.add(r)
    elif r.status != "processed":  # processed is final; ignore out-of-order events
        r.status = status
        if amount:
            r.amount = amount  # the webhook amount is authoritative
    db.flush()
    return r
