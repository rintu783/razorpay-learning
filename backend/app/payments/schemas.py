from pydantic import BaseModel, Field


class CreateOrderRequest(BaseModel):
    # Amount in RUPEES from the app; the service converts it to paise.
    amount: float = Field(gt=0, le=100000, description="Amount in rupees")


class CreateOrderResponse(BaseModel):
    order_id: str
    amount: int  # paise
    currency: str
    key_id: str  # public Key ID only. Never return the secret.
