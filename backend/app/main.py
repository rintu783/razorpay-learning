from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.db import init_db
from app.payments.router import router as payments_router

init_db()
app = FastAPI(title="Razorpay Learning API")
app.include_router(payments_router)

# Flutter web runs on a different origin (localhost:<port>), so the browser needs CORS.
# Demo only: allow all origins. Restrict this in production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}
