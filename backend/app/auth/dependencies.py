from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.tokens import decode_access_token
from app.db import get_db
from app.users.models import User

# auto_error=False so we return our own 401 (with WWW-Authenticate) instead of FastAPI's 403.
_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    """Use as `user: User = Depends(get_current_user)` on any endpoint that needs a logged-in user."""
    unauthorized = HTTPException(
        status_code=401,
        detail="Not authenticated",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if creds is None:
        raise unauthorized
    user_id = decode_access_token(creds.credentials)
    if user_id is None:
        raise unauthorized
    # Load the user on every request, so a deleted account stops working before its token expires.
    user = db.scalar(select(User).where(User.user_id == user_id))
    if user is None:
        raise unauthorized
    return user
