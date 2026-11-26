from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.auth.router import router as auth_router
from app.billing.router import router as billing_router
from app.config import settings
from app.payments.router import router as payments_router
from app.subscriptions.router import router as subscriptions_router
from app.users.router import router as users_router

app = FastAPI(title="Razorpay Learning API")
app.include_router(auth_router)
app.include_router(payments_router)
app.include_router(subscriptions_router)
app.include_router(users_router)
app.include_router(billing_router)

# Flutter web runs on a different origin, so the browser needs CORS. Credentials are allowed (the refresh
# cookie), so origins must be explicit: Starlette answers with the caller's own origin, never "*".
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_origin_regex=settings.cors_origin_regex or None,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


@app.get("/health")
def health():
    return {"status": "ok"}
