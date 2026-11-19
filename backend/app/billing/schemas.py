from datetime import datetime

from pydantic import BaseModel


class HistoryItem(BaseModel):
    invoice_no: str
    order_id: str
    plan_name: str
    amount_rupees: float
    paid_at: datetime
    valid_until: datetime
    status: str  # paid | refunded


class HistoryResponse(BaseModel):
    items: list[HistoryItem]
