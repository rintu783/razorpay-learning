"""One-off: create invoices for paid/refunded payments that have none.

Run from backend/:  .venv/bin/python -m scripts.backfill_invoices
Safe to run twice (skips orders that already have an invoice).
Paid date comes from Razorpay's payment record.
"""
from datetime import datetime, timezone

from sqlalchemy import select

from app.billing import repository as billing_repo
from app.db import SessionLocal
from app.payments import service
from app.payments.models import Payment


def main() -> None:
    client = service._client()
    with SessionLocal() as db:
        payments = db.scalars(
            select(Payment).where(Payment.status.in_(["paid", "refunded"]), Payment.payment_id.is_not(None))
        ).all()
        todo = []
        for p in payments:
            if billing_repo.get_by_order(db, p.order_id) is not None:
                continue
            rp = client.payment.fetch(p.payment_id)
            todo.append((datetime.fromtimestamp(rp["created_at"], tz=timezone.utc), p))
        for paid_at, p in sorted(todo, key=lambda t: t[0]):  # oldest first, so numbers ascend
            inv = billing_repo.create_invoice(db, p, paid_at)
            if inv:
                print(f"{inv.invoice_no}  {p.order_id}  {p.status:9}  paid {paid_at:%Y-%m-%d %H:%M}  until {inv.valid_until:%Y-%m-%d}")
            else:
                print(f"skipped {p.order_id} (no plan purchase)")
        db.commit()
        print(f"done: {len(todo)} payment(s) checked")


if __name__ == "__main__":
    main()
