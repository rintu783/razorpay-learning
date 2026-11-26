from fastapi import APIRouter, Cookie, Depends, HTTPException, Response
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import service
from app.auth.ratelimit import rate_limit
from app.auth.schemas import LoginRequest, RegisterRequest, TokenResponse
from app.auth.security import hash_password, verify_password
from app.auth.tokens import create_access_token
from app.config import settings
from app.db import get_db
from app.users.models import User

router = APIRouter(prefix="/auth", tags=["auth"])

# Named __session because Firebase Hosting strips every other cookie before forwarding to Cloud Run.
COOKIE_NAME = "__session"
# The cookie is only sent to /auth/*, so ordinary API calls never carry the long-lived token.
COOKIE_PATH = "/auth"


def _set_refresh_cookie(response: Response, raw: str) -> None:
    response.set_cookie(
        COOKIE_NAME,
        raw,
        max_age=settings.refresh_token_days * 86400,
        path=COOKIE_PATH,
        domain=settings.cookie_domain,
        secure=settings.cookie_secure,
        httponly=True,  # JavaScript cannot read it, so XSS cannot steal it
        samesite=settings.cookie_samesite,
    )


def _clear_refresh_cookie(response: Response) -> None:
    response.delete_cookie(
        COOKIE_NAME,
        path=COOKIE_PATH,
        domain=settings.cookie_domain,
        secure=settings.cookie_secure,
        httponly=True,
        samesite=settings.cookie_samesite,
    )


def _token_response(response: Response, user_id: str, raw_refresh: str) -> TokenResponse:
    _set_refresh_cookie(response, raw_refresh)
    response.headers["Cache-Control"] = "no-store"  # tokens must not be cached by browsers or proxies
    return TokenResponse(
        access_token=create_access_token(user_id),
        expires_in=settings.access_token_minutes * 60,
    )


_INVALID_LOGIN = HTTPException(status_code=401, detail="Invalid email or password")


@router.post(
    "/register",
    response_model=TokenResponse,
    status_code=201,
    dependencies=[Depends(rate_limit("register", limit=5, window_seconds=60))],
)
def register(body: RegisterRequest, response: Response, db: Session = Depends(get_db)):
    if service.get_user_by_email(db, body.email):
        raise HTTPException(status_code=409, detail="Email already registered")
    user = User(email=body.email, password_hash=hash_password(body.password))
    db.add(user)
    try:
        db.flush()  # assigns user_id; the unique index also catches two simultaneous registrations
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Email already registered")
    raw = service.issue_refresh_token(db, user.user_id)
    db.commit()
    return _token_response(response, user.user_id, raw)


@router.post(
    "/login",
    response_model=TokenResponse,
    dependencies=[Depends(rate_limit("login", limit=10, window_seconds=60))],
)
def login(body: LoginRequest, response: Response, db: Session = Depends(get_db)):
    user = service.get_user_by_email(db, body.email)
    # Always run the password check (even for unknown emails) and return one generic error.
    if not verify_password(body.password, user.password_hash if user else None) or user is None:
        raise _INVALID_LOGIN
    raw = service.issue_refresh_token(db, user.user_id)
    db.commit()
    return _token_response(response, user.user_id, raw)


@router.post(
    "/refresh",
    response_model=TokenResponse,
    dependencies=[Depends(rate_limit("refresh", limit=30, window_seconds=60))],
)
def refresh(
    response: Response,
    db: Session = Depends(get_db),
    refresh_token: str | None = Cookie(default=None, alias=COOKIE_NAME),
):
    result = service.rotate(db, refresh_token) if refresh_token else None
    if result is None:
        # Returned (not raised) so the cookie-clearing header is kept on the 401.
        failed = JSONResponse(status_code=401, content={"detail": "Session expired, please log in again"})
        _clear_refresh_cookie(failed)
        return failed
    user_id, new_raw = result
    return _token_response(response, user_id, new_raw)


@router.post("/logout", status_code=204)
def logout(
    db: Session = Depends(get_db),
    refresh_token: str | None = Cookie(default=None, alias=COOKIE_NAME),
):
    if refresh_token:
        row = service.find_token(db, refresh_token)
        if row:
            service.revoke_family(db, row.family_id)  # ends this login on this device
            db.commit()
    done = Response(status_code=204)
    _clear_refresh_cookie(done)
    return done
