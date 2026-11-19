from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.billing.models import Invoice
from app.payments.models import Payment
from app.subscriptions import repository as sub_repo
from app.subscriptions.plans import PLANS


def get_by_order(db: Session, order_id: str) -> Invoice | None:
    return db.scalar(select(Invoice).where(Invoice.order_id == order_id))


def create_invoice(db: Session, payment: Payment, paid_at: datetime | None = None) -> Invoice | None:
    """Create the invoice for a paid order, once. Returns None if it exists or there is no purchase."""
    if get_by_order(db, payment.order_id) is not None:
        return None
    purchase = sub_repo.get_purchase(db, payment.order_id)
    if purchase is None:
        return None
    paid_at = paid_at or datetime.now(timezone.utc)
    days = PLANS[purchase.plan_id]["days"]
    inv = Invoice(
        invoice_no=f"TMP-{payment.order_id}",  # replaced below once the id is known
        order_id=payment.order_id,
        payment_id=payment.payment_id,
        user_id=purchase.user_id,
        plan_id=purchase.plan_id,
        amount=payment.amount,
        paid_at=paid_at,
        valid_until=paid_at + timedelta(days=days),
    )
    db.add(inv)
    db.flush()
    inv.invoice_no = f"WHK-{paid_at.year}-{inv.id:04d}"
    return inv


def list_for_user(db: Session, user_id: str) -> list[tuple[Invoice, str]]:
    """Invoices with the payment's current status (paid or refunded), newest first."""
    rows = db.execute(
        select(Invoice, Payment.status)
        .join(Payment, Payment.order_id == Invoice.order_id)
        .where(Invoice.user_id == user_id)
        .order_by(Invoice.paid_at.desc(), Invoice.id.desc())
    ).all()
    return [(inv, status) for inv, status in rows]
