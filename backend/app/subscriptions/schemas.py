from datetime import datetime

from pydantic import BaseModel


class PlanInfo(BaseModel):
    id: str
    name: str
    price_rupees: int
    days: int
    features: list[str]


class CheckoutRequest(BaseModel):
    plan_id: str  # only the plan name; the server decides the price


class SubscriptionResponse(BaseModel):
    user_id: str
    plan_id: str
    pro_until: datetime | None = None
    refundable_order_id: str | None = None  # the paid order the user may refund
    refund_status: str | None = None  # latest refund on that order
    plans: list[PlanInfo]
