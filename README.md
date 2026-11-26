# Razorpay Learning Project (Whiskr)

A small subscription demo built to learn Razorpay. Users start on the Basic plan and can upgrade to Pro through Razorpay checkout. TEST MODE only, no real money moves.

Stack: FastAPI + SQLAlchemy + PostgreSQL with Alembic migrations (backend), Flutter web (app), Razorpay `checkout.js`, `reportlab` (PDF invoices).

## What it does
- **Accounts:** register and log in with email and password. Name and phone are optional and set later from **Edit profile**. The session survives a page reload, and **Log out** is on the Account page.
- **Home:** the Whiskr app bar and a round avatar with the user's initials.
- **Account:** avatar, name (or email until a name is set), email, phone, current plan (Basic or Pro), Edit profile, an "Upgrade to Pro" tile and Log out.
- **Billing:**
  - Plan status, price, and a days-used meter while Pro is active.
  - **Upgrade Plan** opens the Razorpay checkout popup.
  - **Cancel** refunds the full payment and returns the user to Basic.
  - **Billing history** lists each payment with date paid, plan, amount, valid-till date and Paid or Refunded status. The print icon opens a PDF invoice.
- Plan changes are made only by Razorpay webhooks. The app never upgrades or downgrades itself; it waits until the backend reports the new plan.

## Plans
| Plan | Price | Length |
|---|---|---|
| Basic | Free | No expiry |
| Pro | Rs 499 | 30 days |

Prices live on the server, so the app can only ask for a plan name.

## Authentication
- Passwords are hashed with Argon2id. Login errors are identical for a wrong password and an unknown email.
- Login returns a short-lived **access token** (JWT, 15 minutes) in the response body. The app keeps it in memory only and sends it as `Authorization: Bearer <token>`.
- A **refresh token** (30 days) is set as a cookie that is `HttpOnly`, `Secure`, `SameSite=Lax` and limited to `Path=/auth`. JavaScript cannot read it, and ordinary API calls do not carry it. Nothing is stored in localStorage.
- `POST /auth/refresh` rotates the refresh token on every use. If an old token is presented again later (a sign of theft), every token from that login is revoked. The database stores only SHA-256 hashes of refresh tokens.
- On a 401 the app refreshes once and repeats the request. Requests that fail together share one refresh.
- Register, login and refresh are rate limited per IP (5, 10 and 30 per minute). The limiter is in memory, so it is per process. Move it to Redis or the reverse proxy before running several workers.
- Every user-facing endpoint requires login and only returns the caller's own data. Another user's order or invoice returns 404, the same as a missing one. The webhook has no login. Its HMAC signature is its authentication.

## Folders
- `backend/app/auth/`: register, login, refresh, logout, tokens, password hashing, rate limit, `get_current_user`
- `backend/app/payments/`: orders, signature check, webhook, refunds
- `backend/app/subscriptions/`: plans and the user's current plan
- `backend/app/billing/`: invoices, billing history, PDF invoice
- `backend/app/users/`: user and refresh-token tables, `GET` and `PATCH /users/me`
- `backend/alembic/`: database migrations
- `backend/tests/`: pytest suite (runs against a separate `razorpay_test` database)
- `backend/scripts/`: one-off scripts (invoice backfill)
- `mobile/lib/`: Flutter app (`auth`, `home`, `account`, `billing`, `subscriptions`, `payments`, `users`)

## API
All endpoints except `/health`, `/auth/*` and `/payments/webhook` need `Authorization: Bearer <access token>`.

| Method and path | Purpose |
|---|---|
| `GET /health` | Health check |
| `POST /auth/register` | Create an account. Returns an access token and sets the refresh cookie |
| `POST /auth/login` | Log in. Same response as register |
| `POST /auth/refresh` | New access token from the refresh cookie (rotates the cookie) |
| `POST /auth/logout` | End this login and clear the cookie |
| `POST /payments/create-order` | Create a Razorpay order |
| `POST /payments/verify` | Verify the checkout signature |
| `GET /payments/status/{order_id}` | Payment status saved by the webhook |
| `POST /payments/webhook` | Razorpay events. The only thing that changes payment status |
| `POST /payments/{order_id}/refund` | Start a full refund |
| `POST /subscriptions/checkout` | Create an order for a plan |
| `GET /subscriptions/me` | Current plan and refund state |
| `GET /users/me` | The logged-in user's account and profile |
| `PATCH /users/me` | Update first name, last name and phone |
| `GET /billing/history` | Payments with invoice numbers and validity |
| `GET /billing/invoices/{order_id}/pdf` | Invoice as a PDF |

## Run it
1. Database (Docker), from `backend/`: `docker compose up -d`. Postgres listens on `localhost:5433` (not 5432, which is often taken).
2. Backend:
   ```
   cd backend
   python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   cp .env.example .env     # add your TEST keys, webhook secret and a JWT_SECRET. Never commit .env
   alembic upgrade head     # create or update the tables
   uvicorn app.main:app --port 8000
   ```
   Generate `JWT_SECRET` with `python -c "import secrets; print(secrets.token_urlsafe(48))"`. The app refuses to start without one (minimum 32 characters).
3. App, in another terminal: `cd mobile && flutter run -d chrome`. To point a build at another API: `flutter build web --dart-define=API_BASE_URL=https://api.example.com`.
4. Webhooks need a public URL. Start a tunnel to port 8000, for example `ngrok http 8000`, then in the Razorpay dashboard (Test mode) go to Developers, then Webhooks, and set the URL to `<tunnel-url>/payments/webhook`.
   - Use the same secret as `RAZORPAY_WEBHOOK_SECRET` in `.env`.
   - Tick these events: `payment.captured`, `payment.failed`, `order.paid`, `refund.created`, `refund.processed`, `refund.failed`.
   - Free tunnel URLs change when the tunnel restarts, so update the dashboard then.
5. Pay with a Razorpay test card, for example `4111 1111 1111 1111` with any future expiry and any CVV.

## Tests
- Backend: `cd backend && pip install -r requirements-dev.txt && python -m pytest`. Needs the Docker database running. It creates and migrates its own `razorpay_test` database and refuses to run against any database whose name does not end in `_test`.
- App: `cd mobile && flutter test`.

## Database
PostgreSQL, schema managed by Alembic.
- After changing a model: `alembic revision --autogenerate -m "what changed"`, review the generated file (Alembic does not detect CHECK constraints), then `alembic upgrade head`.
- Postgres enforces string lengths, which SQLite did not. Size columns for real Razorpay ids (about 20 characters).
- To create invoices for paid payments that have none: `cd backend && .venv/bin/python -m scripts.backfill_invoices` (safe to run twice).

## Production checklist
- Serve over HTTPS, and keep `COOKIE_SECURE=true`.
- Set `CORS_ORIGINS` to the app's exact origin and set `CORS_ORIGIN_REGEX=` (empty). The default regex allows any localhost port for development.
- Serve the app and the API from the same site (for example `app.example.com` and `api.example.com`) so the refresh cookie counts as first-party. Set `COOKIE_DOMAIN` if needed.
- Use a strong `JWT_SECRET` and real database credentials from a secret store, not the dev defaults in `docker-compose.yml`.
- Replace the in-memory rate limiter before running more than one worker.

## Limits of the demo
- No email verification and no password reset yet.
- `POST /payments/create-order` (the generic payment screen) lets a logged-in user choose the amount. Plan purchases are safe because their price is set on the server.
- Web only. `razorpay_flutter` does not support web, so the app uses `checkout.js`.
- Refunds are full refunds only, and a refund finishes only when its webhook arrives. If the tunnel is down, the refund stays pending.
- Invoices have no tax lines and are marked as test-mode invoices.
