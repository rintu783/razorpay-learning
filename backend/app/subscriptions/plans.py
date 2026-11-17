"""Plan catalog. Prices live on the server so the app can never choose its own amount."""
DEMO_USER = "demo-user"  # no login in this demo; one fixed user

PLANS = {
    "basic": {"name": "Basic", "price_rupees": 0, "days": 0, "features": ["Limited usage", "Community support"]},
    "pro": {"name": "Pro", "price_rupees": 499, "days": 30, "features": ["Unlimited usage", "Priority support", "Advanced reports"]},
}
