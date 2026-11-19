from datetime import datetime, timezone

from sqlalchemy import DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Invoice(Base):
    """One row per paid order. Written when the payment becomes `paid`.

    Refund status is not stored here. It is read from payments.status when listing.
    """

    __tablename__ = "invoices"

    id: Mapped[int] = mapped_column(primary_key=True)
    invoice_no: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    order_id: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    payment_id: Mapped[str | None] = mapped_column(String(40), nullable=True)
    user_id: Mapped[str] = mapped_column(String(40), index=True)
    plan_id: Mapped[str] = mapped_column(String(20))
    amount: Mapped[int] = mapped_column(Integer)  # paise
    paid_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    valid_until: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
