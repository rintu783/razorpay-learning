from pydantic import BaseModel, Field


class CreateOrderRequest(BaseModel):
    # Amount in RUPEES from the app; the service converts it to paise.
    amount: float = Field(gt=0, le=100000, description="Amount in rupees")


class VerifyPaymentRequest(BaseModel):
    # The three values Razorpay checkout returns to the app on success.
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


class VerifyPaymentResponse(BaseModel):
    verified: bool
    status: str  # "paid" or "failed"


class CreateOrderResponse(BaseModel):
    order_id: str
    amount: int  # paise
    currency: str
    key_id: str  # public Key ID only. Never return the secret.
