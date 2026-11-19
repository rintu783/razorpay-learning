from sqlalchemy import select
from sqlalchemy.orm import Session

from app.users.models import User

# Fixed placeholder values for the demo user.
_DEMO_PROFILE = dict(
    first_name="Alex",
    last_name="Morgan",
    email="alex.morgan@example.com",
    phone="+1 555 010 2030",
)


def get_or_create(db: Session, user_id: str) -> User:
    user = db.scalar(select(User).where(User.user_id == user_id))
    if user is None:
        user = User(user_id=user_id, **_DEMO_PROFILE)
        db.add(user)
        db.flush()
    return user
