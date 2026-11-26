from pydantic import BaseModel, EmailStr, Field, field_validator


def _normalize_email(v: str) -> str:
    return v.strip().lower()


class RegisterRequest(BaseModel):
    email: EmailStr
    # Max length stops someone from sending a megabyte "password" to burn CPU in Argon2.
    password: str = Field(min_length=8, max_length=128)

    _lower = field_validator("email", mode="after")(_normalize_email)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)

    _lower = field_validator("email", mode="after")(_normalize_email)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds
