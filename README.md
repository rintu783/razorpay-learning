# Razorpay Learning Project

Learn Razorpay integration step by step. Stack: FastAPI (backend) + Flutter (Android). TEST MODE only.

Latest versions checked (Nov 2026): `razorpay` Python SDK 2.0.1, `razorpay_flutter` 1.4.7.

## Folders
- `backend/`: FastAPI app
- `mobile/`: Flutter app
- `notes/`: one lesson per step

## Progress checklist
- [x] 01 [Big picture](notes/01-big-picture.md)
- [ ] 02 Razorpay account and TEST MODE keys
- [ ] 03 Backend setup
- [ ] 04 Create Order API
- [ ] 05 Flutter checkout
- [ ] 06 Razorpay events in Flutter
- [ ] 07 Verify payment signature
- [ ] 08 Test payments
- [ ] 09 Save payment records
- [ ] 10 Webhooks
- [ ] 11 Refunds
- [ ] 12 Reuse checklist
- [ ] 13 Going live
- [ ] 14 Master diagram

## Previewing Mermaid diagrams in VS Code
1. Install the extension "Markdown Preview Mermaid Support" (bierner.markdown-mermaid).
2. Open a lesson `.md` file.
3. Press `Ctrl+Shift+V` (preview) or `Ctrl+K V` (side by side).
(GitHub also renders Mermaid automatically.)

## Quick demo (web, test mode)
1. `cd backend && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt`
2. Copy `backend/.env.example` to `backend/.env` and add TEST keys (never commit it).
3. `uvicorn app.main:app --port 8000`
4. In another terminal: `cd mobile && flutter run -d chrome`

Built for the demo: create-order, checkout (checkout.js), signature verify.
Not built yet: DB records, webhooks, refunds. Note: `razorpay_flutter` does not support web, so the web app uses checkout.js.
