from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    razorpay_key_id: str = ""
    razorpay_key_secret: str = ""
    razorpay_webhook_secret: str = ""
    # Local dev default matches docker-compose.yml (host port 5433).
    database_url: str = "postgresql+psycopg://razorpay:razorpay_dev_password@localhost:5433/razorpay"

    # Auth. No default for the secret: the app refuses to start without one.
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    # Refresh-token cookie. Secure=True needs HTTPS (browsers exempt localhost, so True works locally too).
    cookie_secure: bool = True
    cookie_samesite: str = "lax"  # lax | strict | none
    cookie_domain: str | None = None  # e.g. ".example.com" in production
    rate_limit_enabled: bool = True  # tests switch this off

    # CORS. The browser app and the API are on different origins, and the refresh cookie needs
    # credentialed requests, which forbid "*". Production: list exact origins, comma separated,
    # and set CORS_ORIGIN_REGEX to an empty value.
    cors_origins: str = ""
    # Dev default: any localhost port, because `flutter run -d chrome` picks a random one.
    cors_origin_regex: str = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @field_validator("database_url")
    @classmethod
    def _use_psycopg3_driver(cls, v: str) -> str:
        # Hosted Postgres (Neon etc.) hands out plain postgresql:// URLs, which SQLAlchemy maps to psycopg2.
        # We ship psycopg 3, so select it explicitly.
        for plain in ("postgresql://", "postgres://"):
            if v.startswith(plain):
                return "postgresql+psycopg://" + v[len(plain):]
        return v

    @field_validator("jwt_secret")
    @classmethod
    def _secret_long_enough(cls, v: str) -> str:
        if len(v) < 32:
            raise ValueError("JWT_SECRET must be at least 32 characters")
        return v


settings = Settings()
