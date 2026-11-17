from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    plan_id: Mapped[str] = mapped_column(String(20), default="basic")
    pro_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, onupdate=_now)


class PlanPurchase(Base):
    """Links a Razorpay order to the plan it buys. `applied` makes the upgrade idempotent."""

    __tablename__ = "plan_purchases"

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    user_id: Mapped[str] = mapped_column(String(40))
    plan_id: Mapped[str] = mapped_column(String(20))
    applied: Mapped[bool] = mapped_column(Boolean, default=False)
