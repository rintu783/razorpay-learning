from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


def new_user_id() -> str:
    # Public id used by subscriptions, invoices and tokens. Not the integer primary key,
    # so ids in URLs and tokens are not guessable or sequential.
    return f"usr_{uuid4().hex}"  # 4 + 32 = 36 chars, fits String(40)


class User(Base):
    __tablename__ = "users"
    # Emails are stored lowercased by the app. The constraint makes the database enforce it,
    # so the unique index cannot be bypassed with "A@x.com" vs "a@x.com".
    __table_args__ = (CheckConstraint("email = lower(email)", name="ck_users_email_lowercase"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(String(40), unique=True, index=True, default=new_user_id)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)  # 254 = max email length
    password_hash: Mapped[str] = mapped_column(String(255))
    # Optional profile data, filled in later from the "Update profile" screen.
    first_name: Mapped[str | None] = mapped_column(String(60), nullable=True)
    last_name: Mapped[str | None] = mapped_column(String(60), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(30), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class RefreshToken(Base):
    """One row per issued refresh token. Only a SHA-256 hash is stored, never the token itself,
    so a database leak does not give an attacker usable sessions.

    Tokens form a family (one login = one family). Each refresh revokes the used token and issues
    a new one in the same family. If an already-revoked token is presented again, it was stolen
    or replayed, and the whole family is revoked.
    """

    __tablename__ = "refresh_tokens"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(
        String(40), ForeignKey("users.user_id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)  # sha256 hex
    family_id: Mapped[str] = mapped_column(String(36), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
