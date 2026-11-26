"""Small in-memory fixed-window rate limiter, used on the auth endpoints.

Limits: it is per process and resets on restart. With several workers or servers, each has its own
counters, so move this to Redis (or put limits on the reverse proxy) before scaling out. The key is the
client IP; behind a reverse proxy, configure the proxy headers so request.client is the real client.
"""
import time
from collections import defaultdict, deque
from threading import Lock

from fastapi import HTTPException, Request

from app.config import settings


def rate_limit(name: str, limit: int, window_seconds: int):
    hits: dict[str, deque[float]] = defaultdict(deque)
    lock = Lock()

    def dependency(request: Request) -> None:
        if not settings.rate_limit_enabled:
            return
        key = request.client.host if request.client else "unknown"
        now = time.monotonic()
        with lock:
            q = hits[key]
            while q and now - q[0] > window_seconds:
                q.popleft()
            if len(q) >= limit:
                retry = max(1, int(window_seconds - (now - q[0])))
                raise HTTPException(
                    status_code=429,
                    detail=f"Too many requests for {name}. Try again later.",
                    headers={"Retry-After": str(retry)},
                )
            q.append(now)
            if len(hits) > 10_000:  # keep memory bounded: drop idle keys
                for k in [k for k, v in hits.items() if not v or now - v[-1] > window_seconds]:
                    del hits[k]

    return dependency
