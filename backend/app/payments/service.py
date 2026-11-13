import hashlib
import hmac
import uuid

import razorpay

from app.config import settings


def _client() -> razorpay.Client:
    if not settings.razorpay_key_id or not settings.razorpay_key_secret:
        raise RuntimeError("Razorpay keys are missing in backend/.env")
    return razorpay.Client(auth=(settings.razorpay_key_id, settings.razorpay_key_secret))


def rupees_to_paise(rupees: float) -> int:
    # round() avoids float errors like 10.1 * 100 = 1009.9999
    return round(rupees * 100)


def verify_signature(order_id: str, payment_id: str, signature: str) -> bool:
    """Razorpay signs "order_id|payment_id" with HMAC-SHA256 using the Key Secret.
    We recompute it and compare. Only someone holding the secret can match it."""
    if not settings.razorpay_key_secret:
        raise RuntimeError("Razorpay keys are missing in backend/.env")
    expected = hmac.new(
        settings.razorpay_key_secret.encode(),
        f"{order_id}|{payment_id}".encode(),
        hashlib.sha256,
    ).hexdigest()
    # compare_digest avoids timing attacks
    return hmac.compare_digest(expected, signature)


def create_order(amount_rupees: float) -> dict:
    """Create an order on Razorpay. Needs Key ID + Key Secret (backend only)."""
    return _client().order.create(
        {
            "amount": rupees_to_paise(amount_rupees),
            "currency": "INR",
            "receipt": f"rcpt_{uuid.uuid4().hex[:12]}",  # our own reference, max 40 chars
        }
    )
