from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db import get_db
from app.subscriptions.plans import DEMO_USER
from app.users import repository
from app.users.schemas import UserResponse

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserResponse)
def me(db: Session = Depends(get_db)):
    user = repository.get_or_create(db, DEMO_USER)
    db.commit()
    return UserResponse(
        user_id=user.user_id,
        first_name=user.first_name,
        last_name=user.last_name,
        email=user.email,
        phone=user.phone,
    )
