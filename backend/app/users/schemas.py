import re

from pydantic import BaseModel, ConfigDict, field_validator

_PHONE = re.compile(r"^\+?[0-9 ()\-]{7,30}$")


class UserResponse(BaseModel):
    user_id: str
    email: str
    first_name: str | None
    last_name: str | None
    phone: str | None


class UserUpdate(BaseModel):
    """Fields left out stay unchanged. An empty string or null clears the field."""

    # Rejects unknown fields, so a client cannot try to send email, password_hash or user_id here.
    model_config = ConfigDict(extra="forbid")

    first_name: str | None = None
    last_name: str | None = None
    phone: str | None = None

    @field_validator("first_name", "last_name", "phone", mode="after")
    @classmethod
    def _clean(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        return v or None

    @field_validator("first_name", "last_name", mode="after")
    @classmethod
    def _name_length(cls, v: str | None) -> str | None:
        if v is not None and len(v) > 60:
            raise ValueError("must be at most 60 characters")
        return v

    @field_validator("phone", mode="after")
    @classmethod
    def _phone_format(cls, v: str | None) -> str | None:
        if v is not None and not _PHONE.match(v):
            raise ValueError("must be 7-30 characters: digits, spaces, +, - and parentheses")
        return v
