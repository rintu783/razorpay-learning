import hashlib
import secrets
from datetime import datetime, timedelta, timezone

import jwt

from app.config import settings


def create_access_token(user_id: str) -> str:
    """Short-lived signed JWT. The client keeps it in memory and sends it as a Bearer header."""
    now = datetime.now(timezone.utc)
    claims = {
        "sub": user_id,
        "typ": "access",
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_minutes),
    }
    return jwt.encode(claims, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> str | None:
    """Return the user_id, or None if the token is invalid, expired or not an access token."""
    try:
        claims = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],  # fixed list: blocks the "alg: none" trick
            options={"require": ["exp", "sub"]},
        )
    except jwt.PyJWTError:
        return None
    if claims.get("typ") != "access":
        return None
    return claims["sub"]


def new_refresh_token() -> str:
    """Opaque random string (not a JWT). 48 bytes = 384 bits of randomness."""
    return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> str:
    # SHA-256 is enough here (not Argon2): the token is already high-entropy random, so
    # there is nothing to brute-force, and we need a fast lookup on every refresh.
    return hashlib.sha256(token.encode()).hexdigest()
