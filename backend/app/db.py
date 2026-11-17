from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import settings

# check_same_thread=False: FastAPI runs sync endpoints in a thread pool.
engine = create_engine(settings.database_url, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine, autoflush=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    from app.payments import models  # noqa: F401  (registers tables)
    from app.subscriptions import models as _sub  # noqa: F401

    Base.metadata.create_all(engine)
