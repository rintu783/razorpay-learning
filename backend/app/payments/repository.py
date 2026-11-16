"""All database access for payments lives here."""
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.payments.models import Payment, WebhookEvent

# Allowed status moves. "paid" is final; "failed" may become "paid" (user retries).
_ALLOWED = {"created": {"paid", "failed"}, "failed": {"paid"}, "paid": set()}


def save_order(db: Session, order_id: str, receipt: str, amount: int, currency: str) -> Payment:
    p = Payment(order_id=order_id, receipt=receipt, amount=amount, currency=currency)
    db.add(p)
    db.commit()
    return p


def get_by_order(db: Session, order_id: str) -> Payment | None:
    return db.scalar(select(Payment).where(Payment.order_id == order_id))


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
