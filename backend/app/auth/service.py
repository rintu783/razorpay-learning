from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.auth.tokens import hash_refresh_token, new_refresh_token
from app.config import settings
from app.users.models import RefreshToken, User

# A refresh token used twice within this window is treated as a harmless double request (for
# example two parallel calls from one app start), not as theft. Older reuse revokes the family.
REUSE_GRACE_SECONDS = 10


def _now() -> datetime:
    return datetime.now(timezone.utc)


def get_user_by_email(db: Session, email: str) -> User | None:
    return db.scalar(select(User).where(User.email == email))


def issue_refresh_token(db: Session, user_id: str, family_id: str | None = None) -> str:
    """Create and store a refresh token (hash only). Returns the raw token, shown to the client once."""
    raw = new_refresh_token()
    db.add(
        RefreshToken(
            user_id=user_id,
            token_hash=hash_refresh_token(raw),
            family_id=family_id or str(uuid4()),
            expires_at=_now() + timedelta(days=settings.refresh_token_days),
        )
    )
    return raw


def revoke_family(db: Session, family_id: str) -> None:
    db.execute(
        update(RefreshToken)
        .where(RefreshToken.family_id == family_id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=_now())
    )


def find_token(db: Session, raw: str, lock: bool = False) -> RefreshToken | None:
    stmt = select(RefreshToken).where(RefreshToken.token_hash == hash_refresh_token(raw))
    if lock:
        stmt = stmt.with_for_update()  # serialises two simultaneous refreshes of the same token
    return db.scalar(stmt)


def rotate(db: Session, raw: str) -> tuple[str, str] | None:
    """Exchange a valid refresh token for a new one. Returns (user_id, new_raw_token), or None.

    None means the caller must log in again. A reused (already revoked) token revokes its whole family.
    """
    row = find_token(db, raw, lock=True)
    now = _now()
    if row is None:
        return None
    if row.revoked_at is not None:
        if now - row.revoked_at > timedelta(seconds=REUSE_GRACE_SECONDS):
            revoke_family(db, row.family_id)  # replayed old token: assume theft, kill the session
            db.commit()
        return None
    if row.expires_at <= now:
        return None
    row.revoked_at = now
    new_raw = issue_refresh_token(db, row.user_id, family_id=row.family_id)
    db.commit()
    return row.user_id, new_raw
