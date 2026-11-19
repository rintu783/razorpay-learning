from datetime import timezone

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from app.billing import repository
from app.billing.pdf import build_invoice_pdf
from app.billing.schemas import HistoryItem, HistoryResponse
from app.db import get_db
from app.payments import repository as pay_repo
from app.subscriptions.plans import DEMO_USER, PLANS
from app.users import repository as user_repo

router = APIRouter(prefix="/billing", tags=["billing"])


def _utc(dt):
    """SQLite drops the timezone; stored values are UTC."""
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt


@router.get("/history", response_model=HistoryResponse)
def history(db: Session = Depends(get_db)):
    items = [
        HistoryItem(
            invoice_no=inv.invoice_no,
            order_id=inv.order_id,
            plan_name=PLANS[inv.plan_id]["name"],
            amount_rupees=inv.amount / 100,
            paid_at=_utc(inv.paid_at),
            valid_until=_utc(inv.valid_until),
            status="refunded" if status == "refunded" else "paid",
        )
        for inv, status in repository.list_for_user(db, DEMO_USER)
    ]
    return HistoryResponse(items=items)


@router.get("/invoices/{order_id}/pdf")
def invoice_pdf(order_id: str, db: Session = Depends(get_db)):
    inv = repository.get_by_order(db, order_id)
    if inv is None or inv.user_id != DEMO_USER:
        raise HTTPException(status_code=404, detail="Invoice not found")
    payment = pay_repo.get_by_order(db, order_id)
    user = user_repo.get_or_create(db, inv.user_id)
    db.commit()
    pdf = build_invoice_pdf(
        inv, user, PLANS[inv.plan_id]["name"], refunded=bool(payment and payment.status == "refunded")
    )
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="{inv.invoice_no}.pdf"'},
    )
