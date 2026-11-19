# Razorpay Learning Project (Whiskr)

A small subscription demo built to learn Razorpay. Users start on the Basic plan and can upgrade to Pro through Razorpay checkout. TEST MODE only, no real money moves.

Stack: FastAPI + SQLAlchemy + SQLite (backend), Flutter web (app), Razorpay `checkout.js`, `reportlab` (PDF invoices).

## What it does
- **Home:** the Whiskr app bar and a round avatar with the user's initials.
- **Account:** avatar, name, email, phone, current plan (Basic or Pro) and an "Upgrade to Pro" tile.
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

## Folders
- `backend/app/payments/`: orders, signature check, webhook, refunds
- `backend/app/subscriptions/`: plans and the user's current plan
- `backend/app/billing/`: invoices, billing history, PDF invoice
- `backend/app/users/`: demo user profile
- `backend/scripts/`: one-off scripts (invoice backfill)
- `mobile/lib/`: Flutter app (`home`, `account`, `billing`, `subscriptions`, `payments`, `users`)

## API
| Method and path | Purpose |
|---|---|
| `GET /health` | Health check |
| `POST /payments/create-order` | Create a Razorpay order |
| `POST /payments/verify` | Verify the checkout signature |
| `GET /payments/status/{order_id}` | Payment status saved by the webhook |
| `POST /payments/webhook` | Razorpay events. The only thing that changes payment status |
| `POST /payments/{order_id}/refund` | Start a full refund |
| `POST /subscriptions/checkout` | Create an order for a plan |
| `GET /subscriptions/me` | Current plan and refund state |
| `GET /users/me` | Demo user profile |
| `GET /billing/history` | Payments with invoice numbers and validity |
| `GET /billing/invoices/{order_id}/pdf` | Invoice as a PDF |

## Run it
1. Backend:
   ```
   cd backend
   python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   cp .env.example .env     # add your TEST keys and webhook secret. Never commit .env
   uvicorn app.main:app --port 8000
   ```
2. App, in another terminal: `cd mobile && flutter run -d chrome`
3. Webhooks need a public URL. Start a tunnel to port 8000, for example `ngrok http 8000`, then in the Razorpay dashboard (Test mode) go to Developers, then Webhooks, and set the URL to `<tunnel-url>/payments/webhook`.
   - Use the same secret as `RAZORPAY_WEBHOOK_SECRET` in `.env`.
   - Tick these events: `payment.captured`, `payment.failed`, `order.paid`, `refund.created`, `refund.processed`, `refund.failed`.
   - Free tunnel URLs change when the tunnel restarts, so update the dashboard then.
4. Pay with a Razorpay test card, for example `4111 1111 1111 1111` with any future expiry and any CVV.

## Database
SQLite file `backend/payments.db`, created on first start. There are no migrations: new tables are created automatically, but changes to existing tables are not applied. To create invoices for payments made before invoices existed, run `cd backend && .venv/bin/python -m scripts.backfill_invoices` (safe to run twice).

## Limits of the demo
- No login. A single fixed demo user ("Alex Morgan") is used, and no endpoint has authentication.
- Web only. `razorpay_flutter` does not support web, so the app uses `checkout.js`.
- Refunds are full refunds only, and a refund finishes only when its webhook arrives. If the tunnel is down, the refund stays pending.
- Invoices have no tax lines and are marked as test-mode invoices.
